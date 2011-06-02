#!/usr/bin/perl

use warnings;
use strict;

use POE;
use POE::Component::Server::REST;
use POE::Component::Server::REST::Response;
use Data::Dumper;

use XML::Simple;
use YAML::Tiny qw(Dump Load);

use constant {
      APP_OK => 200,
      APP_CREATED => 201,
      APP_ACCEPTED => 202,
      APP_NONAUTHORATIVE => 203,
      APP_NOCONTENT => 204,
      APP_RESETCONTENT => 205,
      APP_PARTIALCONTENT => 206,

      CLIENT_BADREQUEST => 400,
      CLIENT_UNAUTHORIZED => 401,
      CLIENT_FORBIDDEN => 403,
      CLIENT_NOTFOUND => 404,
      CLIENT_TIMEOUT => 408,

      SERVER_INTERNALERROR => 500,
      SERVER_UNIMPLEMENTED => 501,

	  T_XML => 'text/xml',
	  T_YAML => 'text/yaml',
};


my $servicename = "RESTService";
my $session = 'Example';

my @methods = (
	'GET/things',
	'GET/thing',
	'PUT/thing',
	'POST/thing',
	'DELETE/thing',
);

my @content_types = (
	"text/xml",
	"text/yaml",
);

use Sys::Hostname;

my $address = '0.0.0.0';
my $hostname = hostname();
my $port = 8081; 

POE::Component::Server::REST->new(
    'ALIAS'         =>      $session,
    'ADDRESS'       =>      $address,
    'PORT'          =>      8081,
    'HOSTNAME'      =>      $hostname,
	'CONTENTTYPE'	=>		'text/yaml',
);

POE::Session->create(
    'inline_states' =>      {
		'_start'        =>	\&start,
		'_stop'         =>	\&stop,
		'GET/thing'		=>	\&get_thing,
		'POST/thing'	=>	\&add_thing,
		'PUT/thing'		=>	\&upd_thing,
		'DELETE/thing'	=> 	\&del_thing,
		'GET/things'	=>	\&get_things,
    },
);

POE::Kernel->run;
exit 0;

### Helpers

sub start {
	my $kernel = $_[KERNEL];
	my $heap = $_[HEAP];

	# Some preparations
	$heap->{things} = {
		1 => 'Foo',
		2 => 'Bar',
		3 => 'Slow',
		4 => 'Joe', 
	};

	$kernel->alias_set($servicename);

	# Register Service Methods
	foreach my $m (@methods) {
		$kernel->post( $session, 'ADDMETHOD', $servicename, $m );
	}

}

sub stop {
	my $kernel = $_[KERNEL];

	# Unregister Service Methods	
	foreach my $m (@methods) {
		$kernel->post( $session, 'DELMETHOD', $servicename, $m );
	}
}

# Things
####################

sub get_thing {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	# Check if exists
	if( exists($heap->{things}->{$key}) ) {
		  my $val = $heap->{things}->{$key};

		  # Build YAML response, better if you have objects here which can represent themself in yaml/xml/...
	      $response->content({ 
			'thing' => { 
				'id' => $key, 
				'name' => $val }, 
			});
	      $kernel->post( $session, 'DONE', $response, );
	      return;		
	} else {
		$kernel->post( $session, 'FAULT', $response, CLIENT_NOTFOUND, "NotFound", "Thing $key does not exists."  );
		return;	
	}
}

sub get_things {
      my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	  my $things = [];
	  while( my ($id, $name) = each %{ $heap->{things} }) {
			push(@$things, { id => $id, name => $name } );
	  }
	  $response->content({ things => $things });
      $kernel->post($session, 'DONE', $response);
      return;

}

sub add_thing {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	# POE::Component::Server::REST returns undef if there was an error while parsing the request.
	my $content = $response->restbody;
	unless( $content ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Error parsing document structure"  );
		return;
	}

	# Check structure
	unless( ref($content) eq 'HASH' and exists($content->{thing}) and exists($content->{thing}->{id}) and exists($content->{thing}->{name}) ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Unable to validate structure." );
        return;
	}

	# Check for existence
	if( exists($heap->{things}->{$key}) ) {
		$kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Thing $key exists already." );
		return;
	}

	my $id = $content->{thing}->{id};
	my $name = $content->{thing}->{name};

	# Validate extracted field id
	unless( defined $id ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Thing id needs to be set!" );
        return;
	}

	# Validate extracted field name
    unless( defined $name ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Thing name needs to be set!" );
        return;
    }

	# Add it
	$heap->{things}->{$id} = $name;

	# Done
	$kernel->post( $session, 'DONE', $response, "Done", "Added thing $id -> $name"  );
	return;

}

sub upd_thing {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

    # Parse xml
    my $content = $response->restbody;
    unless( $content ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST,"Bad Request", "Error parsing document structure."  );
        return;
    }

	# Sheck structure
    unless( exists($content->{thing}) and exists($content->{thing}->{id}) && exists($content->{thing}->{name}) ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Unable to validate structure." );
        return;
    }

	# Only proceed if referenced thing does exist
    unless( exists($heap->{things}->{$key}) ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Thing $key does not exist." );
        return;
    }

    my $id = $content->{thing}->{id};
    my $name = $content->{thing}->{name};

    # Validate extracted field id
    unless( defined $id ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Thing id needs to be set!" );
        return;
    }

    # Validate extracted field name
    unless( defined $name ) {
        $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, "Bad Request", "Thing name needs to be set!" );
        return;
    }

	# Update thing
    $heap->{things}->{$id} = $name;

	# Done
	$kernel->post( $session, 'DONE', $response, "Done", "Updated thing $id -> $name"  );
	return;

}

sub del_thing {
    my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	my $params = $response->restbody;

	my $apikey = $response->header('APIKEY');
	unless( $apikey and $apikey eq "raiNaeR2ohnaefex0AeFaig7gujeiQuai8uezaach4oow5chaize9xuxuleiqu0z" ) {
		$kernel->post( $session, 'FAULT', $response, CLIENT_UNAUTHORIZED, 'Access Denied', "You are not privileged to delete things." );
		return;
	}

    # Check if referenced thing does exists
    unless( exists($heap->{things}->{$key}) ) {
            $kernel->post( $session, 'FAULT', $response, CLIENT_BADREQUEST, 'EXISTS', "Thing $key does not exist." );
            return;
    }

	# Delete it	
	delete $heap->{things}->{$key};

	# Done
	$kernel->post( $session, 'DONE', $response, "Done", "Successfully removed ththingg." );
	return;

}

