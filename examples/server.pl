#!/usr/bin/perl

use warnings;
use strict;

use POE;
sub POE::Component::Server::REST::DEBUG() { 1 };
use POE::Component::Server::REST;
use HTTP::Status qw(:constants);

use constant {
	  T_XML => 'text/xml',
	  T_YAML => 'text/yaml',
};


# This is OUR session
my $name = "library";

# This is the POE..REST server
my $service = 'restservice';

my $methods = {
	'_start'        =>  \&start,
	'_stop'         =>  \&stop,
	'GET/author'     =>  \&get_author,
	'GET/author/douglas/adams' => \&get_special,
	'POST/author'    =>  \&add_author,
	'PUT/author'     =>  \&upd_author,
	'DELETE/author'  =>  \&del_author,
	'GET/authors'    =>  \&get_authors,
};

use Sys::Hostname;

my $address = '0.0.0.0';
my $hostname = hostname();
my $port = 8081; 

POE::Component::Server::REST->new(
    'ALIAS'         =>      $service,
    'ADDRESS'       =>      $address,
    'PORT'          =>      $port,
    'HOSTNAME'      =>      $hostname,
	'CONTENTTYPE'	=>	'text/json',
);

POE::Session->create(
    'inline_states' => $methods    
);

POE::Kernel->run;
exit 0;

### Helpers

sub start {
	my $kernel = $_[KERNEL];
	my $heap = $_[HEAP];

	# Some preparations
	$heap->{authors} = {
		1 => 'Hemmingway',
		2 => 'Aldous Huxley',
		3 => 'George Orwell',
		4 => 'Humberto Eco', 
	};

	# Necessary in order to let POE..REST server
    # know where to forward calls to
	$kernel->alias_set($name);

	# Register Service Methods
	foreach my $m (keys %$methods) {
		$kernel->post( $service, 'ADDMETHOD', $name, $m );
	}

}

sub stop {
	my $kernel = $_[KERNEL];

	# Unregister Service Methods	
	foreach my $m (keys %$methods) {
		$kernel->post( $service, 'DELMETHOD', $name, $m );
	}
}

# Authors
####################

sub get_author {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	# Check if exists
	if( exists($heap->{authors}->{$key}) ) {
		  my $val = $heap->{authors}->{$key};

		  # Build YAML response, better if you have objects here which can represent themself in yaml/xml/...
	      $response->content({ 
			'author' => { 
				'id' => $key, 
				'name' => $val }, 
			});
	      $kernel->post( $service, 'DONE', $response, );
	      return;		
	} else {
		$kernel->post( $service, 'FAULT', $response, HTTP_NOT_FOUND, "NotFound", "Author $key does not exists."  );
		return;	
	}
}

sub get_authors {
      my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	  my $authors = [];
	  while( my ($id, $name) = each %{ $heap->{authors} }) {
			push(@$authors, { id => $id, name => $name } );
	  }
	  $response->content({ authors => $authors });
      $kernel->post($service, 'DONE', $response);
      return;

}

sub get_special {
    my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	# Build YAML response, better if you have objects here which can represent themself in yaml/xml/...
	$response->content({
	'author' => {
		'id' => 4711,
		'name' => "Douglas Adams" },
	});
	$kernel->post( $service, 'DONE', $response, );
	return;
}

sub add_author {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	# POE::Component::Server::REST returns undef if there was an error while parsing the request.
	my $content = $response->restbody;
	unless( $content ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Error parsing document structure"  );
		return;
	}

	# Check structure
	unless( ref($content) eq 'HASH' and exists($content->{author}) and exists($content->{author}->{id}) and exists($content->{author}->{name}) ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Unable to validate structure." );
        return;
	}

	# Check for existence
	if( exists($heap->{authors}->{$key}) ) {
		$kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Author $key exists already." );
		return;
	}

	my $id = $content->{author}->{id};
	my $name = $content->{author}->{name};

	# Validate extracted field id
	unless( defined $id ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Author id needs to be set!" );
        return;
	}

	# Validate extracted field name
    unless( defined $name ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Author name needs to be set!" );
        return;
    }

	# Add it
	$heap->{author}->{$id} = $name;

	# Done
	$kernel->post( $service, 'DONE', $response, "Done", "Added author $id -> $name"  );
	return;

}

sub upd_author {
	my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

    # Parse xml
    my $content = $response->restbody;
    unless( $content ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST,"Bad Request", "Error parsing document structure."  );
        return;
    }

	# Sheck structure
    unless( exists($content->{author}) and exists($content->{author}->{id}) && exists($content->{author}->{name}) ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Unable to validate structure." );
        return;
    }

	# Only proceed if referenced author does exist
    unless( exists($heap->{authors}->{$key}) ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Author $key does not exist." );
        return;
    }

    my $id = $content->{author}->{id};
    my $name = $content->{author}->{name};

    # Validate extracted field id
    unless( defined $id ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Author id needs to be set!" );
        return;
    }

    # Validate extracted field name
    unless( defined $name ) {
        $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Bad Request", "Author name needs to be set!" );
        return;
    }

	# Update author
    $heap->{authors}->{$id} = $name;

	# Done
	$kernel->post( $service, 'DONE', $response, "Done", "Updated author $id -> $name"  );
	return;

}

sub del_author {
    my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

	my $params = $response->restbody;

	my $apikey = $response->header('APIKEY');
	unless( $apikey and $apikey eq "raiNaeR2ohnaefex0AeFaig7gujeiQuai8uezaach4oow5chaize9xuxuleiqu0z" ) {
		$kernel->post( $service, 'FAULT', $response, HTTP_UNAUTHORIZED, 'Access Denied', "You are not privileged to delete authors." );
		return;
	}

    # Check if referenced author does exists
    unless( exists($heap->{authors}->{$key}) ) {
            $kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, 'EXISTS', "Author $key does not exist." );
            return;
    }

	# Delete it	
	delete $heap->{authors}->{$key};

	# Done
	$kernel->post( $service, 'DONE', $response, "Done", "Successfully removed the author." );
	return;

}

