#!/usr/bin/perl

use warnings;
use strict;

use POE;
use POE::Component::Server::REST;
use HTTP::Status qw(:constants);

use constant {
	  T_XML => 'text/xml',
	  T_YAML => 'text/yaml',
};


# This is OUR session
my $name = "THING";

# This is the POE..REST server
my $service = 'restservice';

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
    'ALIAS'         =>      $service,
    'ADDRESS'       =>      $address,
    'PORT'          =>      8081,
    'HOSTNAME'      =>      $hostname,
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

	# Necessary in order to let POE..REST server
    # know where to forward calls to
	$kernel->alias_set($name);

	# Register Service Methods
	foreach my $m (@methods) {
		$kernel->post( $service, 'ADDMETHOD', $name, $m );
	}

}

sub stop {
	my $kernel = $_[KERNEL];

	# Unregister Service Methods	
	foreach my $m (@methods) {
		$kernel->post( $service, 'DELMETHOD', $name, $m );
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
	      $kernel->post( $service, 'DONE', $response, );
	      return;		
	} else {
		$kernel->post( $service, 'FAULT', $response, HTTP_NOT_FOUND, "NotFound", "Thing $key does not exists."  );
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
      $kernel->post($service, 'DONE', $response);
      return;

}

sub add_thing {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	# POE::Component::Server::REST returns undef if there was an error while parsing the request.
	my $content = $response->restbody;
	unless( $content ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Error parsing document structure"  );
		return;
	}

	# Check structure
	unless( ref($content) eq 'HASH' and exists($content->{thing}) and exists($content->{thing}->{id}) and exists($content->{thing}->{name}) ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Unable to validate structure." );
        return;
	}

	# Check for existence
	if( exists($heap->{things}->{$key}) ) {
		$kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Thing $key exists already." );
		return;
	}

	my $id = $content->{thing}->{id};
	my $name = $content->{thing}->{name};

	# Validate extracted field id
	unless( defined $id ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Thing id needs to be set!" );
        return;
	}

	# Validate extracted field name
    unless( defined $name ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Thing name needs to be set!" );
        return;
    }

	# Add it
	$heap->{things}->{$id} = $name;

	# Done
	$kernel->post( $service, 'DONE', $response, "Done", "Added thing $id -> $name"  );
	return;

}

sub upd_thing {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

    # Parse xml
    my $content = $response->restbody;
    unless( $content ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST,"Bad Request", "Error parsing document structure."  );
        return;
    }

	# Sheck structure
    unless( exists($content->{thing}) and exists($content->{thing}->{id}) && exists($content->{thing}->{name}) ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Unable to validate structure." );
        return;
    }

	# Only proceed if referenced thing does exist
    unless( exists($heap->{things}->{$key}) ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Thing $key does not exist." );
        return;
    }

    my $id = $content->{thing}->{id};
    my $name = $content->{thing}->{name};

    # Validate extracted field id
    unless( defined $id ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Thing id needs to be set!" );
        return;
    }

    # Validate extracted field name
    unless( defined $name ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Thing name needs to be set!" );
        return;
    }

	# Update thing
    $heap->{things}->{$id} = $name;

	# Done
	$kernel->post( $service, 'DONE', $response, "Done", "Updated thing $id -> $name"  );
	return;

}

sub del_thing {
    my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	my $params = $response->restbody;

	my $apikey = $response->header('APIKEY');
	unless( $apikey and $apikey eq "raiNaeR2ohnaefex0AeFaig7gujeiQuai8uezaach4oow5chaize9xuxuleiqu0z" ) {
		$kernel->post( $service, 'FAULT', $response, HTTP_UNAUTHORIZED, 'Access Denied', "You are not privileged to delete things." );
		return;
	}

    # Check if referenced thing does exists
    unless( exists($heap->{things}->{$key}) ) {
            $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, 'EXISTS', "Thing $key does not exist." );
            return;
    }

	# Delete it	
	delete $heap->{things}->{$key};

	# Done
	$kernel->post( $service, 'DONE', $response, "Done", "Successfully removed ththingg." );
	return;

}

