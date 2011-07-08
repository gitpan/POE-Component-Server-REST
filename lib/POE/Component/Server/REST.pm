package POE::Component::Server::REST;

use strict;
use warnings;

our $VERSION = '1.10';

use Carp qw(croak confess cluck longmess);

# Import the proper POE stuff
use POE;
use POE::Session;
use POE::Component::Server::SimpleHTTP;
use Data::Dumper;
use URI::Split qw(uri_split);
use HTTP::Status qw(:constants);

use XML::Simple;
use YAML::Tiny qw(Load Dump);
use JSON;

# Our own modules
use POE::Component::Server::REST::Response;

use constant {
	T_YAML	=> 'text/yaml',
	T_XML	=> 'text/xml',
	T_JSON	=> 'text/json',
};

my $DEFAULT_CONTENT = T_JSON;
my $DEFAULT_NODE = '/';

# Set some constants
BEGIN {
	*DEBUG = sub () { 0 } unless defined(&DEBUG);
}

sub debug {
	warn("DEBUG: ".(shift)."\n");
}

sub new {
    # Get the OOP's type
    my $type = shift;

    # Sanity checking
    if ( @_ & 1 ) {
        croak('POE::Component::Server::REST->new needs even number of options');
    }

    # The options hash
    my %opt = @_;

    # Our own options
    my ( $ALIAS, $ADDRESS, $PORT, $HEADERS, $HOSTNAME, $CONTENTTYPE, $SIMPLEHTTP );

    # You could say I should do this: $Stuff = delete $opt{'Stuff'}
    # But, that kind of behavior is not defined, so I would not trust it...

    # Get the session alias
    if ( exists( $opt{'ALIAS'} ) and defined( $opt{'ALIAS'} ) and length( $opt{'ALIAS'} ) ) {
        $ALIAS = $opt{'ALIAS'};
        delete $opt{'ALIAS'};
    } else {

        # Set the default
        $ALIAS = 'rest';
		debug("Using default ALIAS $ALIAS") if DEBUG;

        # Remove any lingering ALIAS
        if ( exists $opt{'ALIAS'} ) {
            delete $opt{'ALIAS'};
        }
    }

    # Get the PORT
    if ( exists($opt{'PORT'}) and defined($opt{'PORT'}) and length( $opt{'PORT'} ) ) {
        $PORT = $opt{'PORT'};
        delete $opt{'PORT'};
    } else {

        # Debugging info...
		debug('Using default PORT = 80') if DEBUG;

        # Set the default
        $PORT = 80;

        # Remove any lingering PORT
        if ( exists $opt{'PORT'} ) {
            delete $opt{'PORT'};
        }
    }

    # Get the ADDRESS
    if ( exists($opt{'ADDRESS'}) and defined($opt{'ADDRESS'}) and length($opt{'ADDRESS'}) ) {
        $ADDRESS = $opt{'ADDRESS'};
        delete $opt{'ADDRESS'};
    } else {
        croak('ADDRESS is required to create a new POE::Component::Server::REST instance!');
    }

    # Get the HEADERS
    if ( exists($opt{'HEADERS'}) and defined($opt{'HEADERS'}) ) {

        # Make sure it is ref to hash
        if ( ref $opt{'HEADERS'} and ref( $opt{'HEADERS'} ) eq 'HASH' ) {
            $HEADERS = $opt{'HEADERS'};
            delete $opt{'HEADERS'};
        } else {
            croak('HEADERS must be a reference to a HASH!');
        }
    } else {

        # Debugging info...
		debug('Using default HEADERS ( SERVER => POE::Component::Server::REST/' . $VERSION . ' )') if DEBUG;

        # Set the default
        $HEADERS = { 'Server' => 'POE::Component::Server::REST/' . $VERSION, };

        # Remove any lingering HEADERS
        if ( exists $opt{'HEADERS'} ) {
            delete $opt{'HEADERS'};
        }
    }

    # Get the HOSTNAME
    if ( exists($opt{'HOSTNAME'}) and defined($opt{'HOSTNAME'}) and length($opt{'HOSTNAME'}) ) {
        $HOSTNAME = $opt{'HOSTNAME'};
        delete $opt{'HOSTNAME'};
    } else {

        # Debugging info...
		debug('Letting POE::Component::Server::SimpleHTTP create a default HOSTNAME') if DEBUG;

        # Set the default
        $HOSTNAME = undef;

        # Remove any lingering HOSTNAME
        if ( exists $opt{'HOSTNAME'} ) {
            delete $opt{'HOSTNAME'};
        }
    }

    # Get the CONTENTTYPE
    if ( exists($opt{'CONTENTTYPE'}) and defined($opt{'CONTENTTYPE'}) and length($opt{'CONTENTTYPE'}) ) {
        $CONTENTTYPE = $opt{'CONTENTTYPE'};
        delete $opt{'CONTENTTYPE'};
		my $types = [ T_YAML, T_XML, T_JSON ];
		croak("CONTENTTYPE needs to be of: ".join(",",@$types)) unless ( grep($CONTENTTYPE, @$types) );
    } else {

        # Set the default
        $CONTENTTYPE = $DEFAULT_CONTENT;
		debug("Using default CONTENTTYPE ( $CONTENTTYPE )") if DEBUG;

        # Remove any lingering CONTENTTYPE
        if ( exists $opt{'CONTENTTYPE'} ) {
            delete $opt{'CONTENTTYPE'};
        }
    }

    # Get the SIMPLEHTTP
    if ( exists($opt{'SIMPLEHTTP'}) and defined($opt{'SIMPLEHTTP'}) and (ref($opt{'SIMPLEHTTP'}) eq 'HASH') ) {
        $SIMPLEHTTP = $opt{'SIMPLEHTTP'};
        delete $opt{'SIMPLEHTTP'};
    }

    # Anything left over is unrecognized
    if (DEBUG) {
        if ( keys %opt > 0 ) {
            croak( 'Unrecognized options were present in POE::Component::Server::REST->new -> ' . join( ', ', keys %opt ) );
        }
    }

    # Create the POE Session!
    POE::Session->create(
        'inline_states' => {

            # Generic stuff
            '_start' => \&StartServer,
            '_stop'  => sub { },
            '_child' => \&SmartShutdown,

            # Shuts down the server
            'SHUTDOWN'    => \&StopServer,
            'STOPLISTEN'  => \&StopListen,
            'STARTLISTEN' => \&StartListen,

            # Adds/deletes Methods
            'ADDMETHOD'      => \&AddMethod,
            'DELMETHOD'      => \&DeleteMethod,
            'DELSERVICE'     => \&DeleteService,
            'ADDCONTENTTYPE' => \&AddContentType,
            'DELCONTENTTYPE' => \&DelContentType,

            # Transaction handlers
            'Got_Request' => \&TransactionStart,
            'FAULT'       => \&TransactionFault,
            'RAWFAULT'    => \&TransactionFault,
            'DONE'        => \&TransactionDone,
            'RAWDONE'     => \&TransactionDone,
            'CLOSE'       => \&TransactionClose,
        },

        # Our own heap
        'heap' => {
			'TREE'			 => {},
            'INTERFACES'     => {},
            'CONTENT'        => {},
            'ALIAS'          => $ALIAS,
            'ADDRESS'        => $ADDRESS,
            'PORT'           => $PORT,
            'HEADERS'        => $HEADERS,
            'HOSTNAME'       => $HOSTNAME,
            'CONTENTTYPE' 	 => $CONTENTTYPE,
            'SIMPLEHTTP'     => $SIMPLEHTTP,
        },
    ) or die 'Unable to create a new session!';

    # Return success
    return 1;
}

sub unmarshall {
    my ($body, $format) = @_;

	my $struct;
    if ( defined($body) and defined($format) ) {

		if( $format eq T_XML) {
	        $struct = eval { XMLin($body, KeepRoot => 1 ) };
		}

		if( $format eq T_YAML ) {
			$struct = eval { Load($body) };
		}

		if( $format eq T_JSON ) {
			$struct = eval { from_json($body, { utf8 => 1 }) };
		}

		return if($@);
    }
	return $struct;
}

sub marshall {
	my ($struct, $format) = @_;

	my $string;	
	if ( defined($struct) and defined($format) ) {

		if( $format eq T_XML) {
			$string = eval { XMLout( $struct, KeepRoot => 1, XMLDecl => 1, NoAttr => 1 ) };
		}
		
		if( $format eq T_YAML ) {
			$string = eval { Dump($struct) };
		}

		if( $format eq T_JSON ) {
			$string = eval { to_json($struct, { pretty => 1, utf8 => 1 }) };
		}

		return if($@);
	}
	return $string;
}

sub build_response {
	my ( $short, $detail, $content ) = @_;
	return {
		result => {
			short => $short,
			detail => $detail,
			content => $content,
		},
	};		
}

# Creates the server
sub StartServer {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

    # Set the alias
    $kernel->alias_set( $heap->{'ALIAS'} );

    # Create the webserver!
    POE::Component::Server::SimpleHTTP->new(
        'ALIAS'    => $heap->{'ALIAS'} . '-BACKEND',
        'ADDRESS'  => $heap->{'ADDRESS'},
        'PORT'     => $heap->{'PORT'},
        'HOSTNAME' => $heap->{'HOSTNAME'},
        'HEADERS'  => $heap->{'HEADERS'},
        'HANDLERS' => [
            {
                'DIR'     => '.*',
                'SESSION' => $heap->{'ALIAS'},
                'EVENT'   => 'Got_Request',
            },
        ],
        (
            defined($heap->{'SIMPLEHTTP'}) ? ( %{ $heap->{'SIMPLEHTTP'} } ): ()
        ),
    ) or die 'Unable to create the HTTP Server';

    # Success!
    return;
}

# Shuts down the server
sub StopServer {
	my ($kernel, $heap, $how) = @_[KERNEL, HEAP, ARG0];

    # Tell the webserver to die!
    if ( defined($how) and ($how eq 'GRACEFUL') ) {
        # Shutdown gently...
        $kernel->call( $heap->{'ALIAS'} . '-BACKEND', 'SHUTDOWN', 'GRACEFUL' );
    } else {
        # Shutdown NOW!
        $kernel->call( $heap->{'ALIAS'} . '-BACKEND', 'SHUTDOWN' );
    }

    # Success!
    return;
}

# Stops listening for connections
sub StopListen {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

    # Tell the webserver this!
    $kernel->call( $heap->{'ALIAS'} . '-BACKEND', 'STOPLISTEN' );

    # Success!
    return;
}

# Starts listening for connections
sub StartListen {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

    # Tell the webserver this!
    $kernel->call( $heap->{'ALIAS'} . '-BACKEND', 'STARTLISTEN' );

    # Success!
    return;
}

# Watches for SimpleHTTP shutting down and shuts down ourself
sub SmartShutdown {
	my ($kernel, $heap, $type, $ref, $params) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2];

    # Check for real shutdown
    if ( $type eq 'lose' ) {

        # Remove our alias
        $kernel->alias_remove( $heap->{'ALIAS'} );

        # Debug stuff
		debug('Received _child event from SimpleHTTP, shutting down') if DEBUG;
    }

    # All done!
    return;
}

# Adds a method
sub AddMethod {
    # ARG0: Session alias, ARG1: Session event, ARG2: Service name, ARG3: Method name
    my ( $kernel, $heap, $alias, $event, $service, $method ) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3];

    # Validate parameters
    unless ( defined($alias) and length($alias) ) {
		debug('Did not get a Session Alias') if DEBUG;
        return;
    }

    unless ( defined($event) and length($event) ) {
		debug('Did not get a Session Event') if DEBUG;
        return;
    }

    unless ( defined($service) and length($service) ) {
		debug('Using Session Alias as Service Name') if DEBUG;
        $service = $alias;
    }

    unless ( defined($method) and length($method) ) {
		debug('Using Session Event as Method Name') if DEBUG;
        $method = $event;
    }

	$service = lc($service);

    # If we are debugging, check if we overwrote another method
    if (DEBUG) {
        if ( exists $heap->{'INTERFACES'}->{$service} ) {
            if ( exists $heap->{'INTERFACES'}->{$service}->{$method} ) {
                debug('Overwriting old method entry in the registry ( ' . $service . ' -> ' . $method . ' )') if DEBUG;
            }
        }
    }

	# Initialize service in TREE if not present
	unless( exists $heap->{TREE}->{$service} ) {
		$heap->{TREE}->{$service} = {};
	}

	# Add it to our method tree
	my @parts = split(/\//, $method);
    my $max = scalar(@parts);
    my $tmp = $heap->{TREE}->{$service};
    foreach my $part (@parts) {
        $max--;
        $tmp->{$part} = {} unless exists($tmp->{$part});
        $tmp = $tmp->{$part};
		# Set the default node at the leaf
        $tmp->{$DEFAULT_NODE} = [ $alias, $event] if $max == 0;
    }

    # Add it to our INTERFACES
    $heap->{'INTERFACES'}->{$service}->{$method} = [ $alias, $event ];
	debug("Added method $method to service $service") if DEBUG;

    # Return success
    return 1;
}

# Deletes a method
sub DeleteMethod {
    # ARG0: Service name, ARG1: Service method name
    my ( $kernel, $heap, $service, $method ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];

	$service = lc($service);

    # Validation
    if ( defined($service) and length($service) ) {

        # Validation
        if ( defined($method) and length($method) ) {

				# Traversing the tree!
				my @parts = split(/\//, $method);
				my $max = scalar(@parts);
				my $path = $heap->{TREE}->{$service};
				my $tmp = {};
				foreach my $part (@parts) {
					$max--;
					if(exists($path->{$part})) {
						if($max > 0) {
							# We havent finished searching yet
							$tmp->{$part} = {};
							$tmp = $tmp->{$part};
							$path = $path->{$part};
						} else {
							# We should be at the leaf
							if( keys(%{$path->{$part}}) == 1 && exists($path->{$part}->{$DEFAULT_NODE})) {
								delete($path->{$part});
								debug("Removed $method in tree") if DEBUG;
							} else {
								debug("Element '$part' is not empty.") if DEBUG;
								return;
							}
						}
					} else {
						debug("Method $method is nonexistent.") if DEBUG;
						return;
					}
				}

                # Delete it!
                delete $heap->{'INTERFACES'}->{$service}->{$method};
				debug("Removed method $method for service $service.") if DEBUG;

                # Check to see if the service now have no methods
                if ( keys( %{ $heap->{'INTERFACES'}->{$service} } ) == 0 ) {

                    # Debug stuff
					debug("Service $service contains no methods, removing it!") if DEBUG;

                    # Delete it!
                    delete $heap->{'INTERFACES'}->{$service};
                }

                # Return success
                return 1;

        } else {
			debug("Did not get a method to delete in Service -> $service") if DEBUG;
        }
    } else {
		debug('Received no arguments!') if DEBUG;
    }

    return;
}

# Deletes a service
sub DeleteService {
    # ARG0: Service name
    my ( $kernel, $heap, $service) = @_[ KERNEL, HEAP, ARG0 ];

    # Validation
    if ( defined($service) and length($service) ) {

        # Validation
        if ( exists $heap->{'INTERFACES'}->{$service} ) {

            # Delete it!
            delete $heap->{'INTERFACES'}->{$service};
			debug("Deleted Service $service") if DEBUG;

            # Return success!
            return 1;
        } else {
            # Error!
			debug("Tried to delete a Service that does not exist! -> $service") if DEBUG;
        }
    } else {
        # No arguments!
		debug('Received no arguments!') if DEBUG;
    }

    return;
}

# Got a request, handle it!
sub TransactionStart {

    # ARG0 = HTTP::Request, ARG1 = HTTP::Response, ARG2 = dir that matched
    my ( $kernel, $heap, $request, $response, $dir ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];

	debug("<<<<<< NEW REQUEST >>>>>>>") if DEBUG;

    # Check for error in parsing of request
    unless ( defined $request ) {
        $kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', 'Unable to parse HTTP query', );
        return;
    }

    # We need the method name
    my $type = $request->method();
    debug("Request is of method: " . uc($type) ) if DEBUG;

	# Validate REQUEST Method ie. POST, PUT, DELETE, GET
    unless ( defined($type) and length($type) ) {
        $kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', 'Invalid Request Method', );
        return;
    }

	# Validate given ContentType
    debug("Received header: " . $request->header('Content-Type') ) if DEBUG;
    my ( $contenttype, undef ) = split( m/;/, $request->header('Content-Type') || '', 2 );
    unless ( $request->header('Content-Type') and $contenttype eq $heap->{'CONTENTTYPE'} ) {
        $kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', 'Content-Type must be of: '.$heap->{CONTENTTYPE} );
        return;
    }

	# extract the path
	my $uri = $request->uri;
	debug("Extracted URI: $uri") if DEBUG;
	my (undef, undef, $path, undef) = uri_split($uri);

    # Validate the service
    my $service;
	unless ( defined($path) and ($path =~ m/\/(\w+)(\/.+)?/) ) {
            $kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', 'Unable to parse the URI for the service', );
            return;
    } else {
        # Set the service
        $service = lc($1);
		debug("Extracted service: $service") if DEBUG;
		$path = $2;
		debug("Extracted path: $path") if DEBUG;
    }

    # Check to see if this service exists
    unless ( exists($heap->{'TREE'}->{$service}) ) {
		my $services = join(",",keys %{$heap->{'TREE'}});
        $kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', "Unknown service: $service - valid ones: [$services]");
        return;
    } else {
        debug("Found service $service to be valid.") if DEBUG;
    }
    
	# Validate the Type in TREE
	unless( exists $heap->{TREE}->{$service}->{$type}) {
		$kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', "There is no such type $type defined for the service $service");
		return;
	}

	# Find the farest-valid method, key and alias/event in tree
	$path =~ s/^\///;
	my @resources = split(/\//, $path);
	my $tmp = $heap->{TREE}->{$service}->{$type};
	my $leaf;
	foreach my $key (@resources) {
		debug("-- Probing $key") if DEBUG;
		if( exists $tmp->{$key} ) {
			$tmp = $tmp->{$key};
			$leaf = $tmp->{$DEFAULT_NODE} if exists($tmp->{$DEFAULT_NODE});
			debug("tmp leaf: ".$leaf->[1]) if DEBUG;
		} 
	}

	# Validate extracted leaf
	unless( $leaf ) {
		$kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request', "Invalid method in hierarchy.");
		return;
	}
	debug("Using leaf: ".Dumper($leaf)) if DEBUG;

	# Get the method
	my $method = $leaf->[1];
	debug("Extracted method: $method") if DEBUG;
	
	# Check to see if this method exists
    unless ( exists $heap->{'INTERFACES'}->{$service}->{$method} ) {
        debug("Method $method does not exists") if DEBUG;
        $kernel->yield( 'FAULT', $response, HTTP_BAD_REQUEST, 'Bad Request',
            "Unknown method: $method (Available: " . join( ",", keys %{ $heap->{'INTERFACES'}->{$service} } ) . ")",
        );
        return;
    }

	# Extract the key
	my $key = "$type/$path";
	$key =~ s/$method//;
	$key =~ s/^\///;
	debug("Extracted key: ". ($key ? $key : '')) if DEBUG;
    
    # Check for errors
    if ($@) {
        $kernel->yield( 'FAULT', $response, HTTP_INTERNAL_SERVER_ERROR, 'Application Faulted', "Some errors occured while processing the request: $@", );
        return;
    }

    # Check the headers for the mustUnderstand attribute, and Fault if it is present
    my $head_count = 1;
    my @headers    = ();

	debug("Request content: ".$request->content()."\n") if DEBUG;

    # Extract the body
    my $body = unmarshall($request->content, $heap->{CONTENTTYPE});

    # If it is an empty string, turn it into undef
    if ( defined($body) and !ref($body) and $body eq '' ) {
        $body = undef;
    }

    # Hax0r the Response to include our stuff!
    $response->{'RESTMETHOD'}  = $method;
    $response->{'RESTBODY'}    = $body;
    $response->{'RESTSERVICE'} = $service;
    $response->{'RESTREQUEST'} = $request;
    $response->{'RESTURI'}     = $uri;
	$response->{'RESTHEADERS'} = ( @headers ? \@headers : undef );

    # ReBless it ;)
    bless( $response, 'POE::Component::Server::REST::Response' );
	debug("Unmarshalled content: ".Dumper($body)) if DEBUG;

    # Send it off to the handler!
	my ( $alias, $event ) = @$leaf;
    $kernel->post( $alias, $event, $response, $key );

    # Debugging stuff
	debug("Sending off to the handler: Service $service -> Method $method for " . $response->connection->remote_ip()) if DEBUG;

    # All done!
    return;
}

# Creates the fault and sends it off
sub TransactionFault {
    # ARG0 = SOAP::Response, ARG1 = SOAP faultcode, ARG2 = SOAP faultstring, ARG3 = SOAP Fault Detail, ARG4 = SOAP Fault Actor
    my ( $kernel, $heap, $response, $fault_code, $fault_string, $fault_detail, $fault_actor ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3, ARG4 ];

	debug("<<<<<< BUILDING FAULT >>>>>>>") if DEBUG;

    # Make sure we have a REST::Response object here :)
    unless ( defined $response ) {
        debug('Received FAULT event but no arguments!') if DEBUG;
        $response = POE::Component::Server::REST::Response->new();
    }

	# Set default for short and detail
	$fault_string = "Fault" unless $fault_string;
	$fault_detail = "Application faulted" unless $fault_detail;

	# Set default code
    $response->code( $fault_code );
	$response->code(HTTP_INTERNAL_SERVER_ERROR) unless $fault_code;

	# Build answer
	$response->content(undef) unless $response->content;
	$response->content( build_response($fault_string, $fault_detail, $response->content) );

	# Set Content-Type header
	$response->header( 'Content-Type', $heap->{CONTENTTYPE} );

    debug("Fault code: " . $response->code ) if DEBUG;
    debug("Fault header: \n" . $response->headers->as_string ) if DEBUG;
    debug("Fault content: " . Dumper($response->content) ) if DEBUG;

	# Marhsall the answer
	$response->content( marshall($response->content, $response->header('Content-Type')) );

    # Send it off to the backend!
    $kernel->post( $heap->{'ALIAS'} . '-BACKEND', 'DONE', $response );

	debug('Finished processing ' . $_[STATE] . ' for ' . $response->connection->remote_ip()) if DEBUG;
	debug("Sent fault: ".$response->content() . "\n") if DEBUG;

    # All done!
    return;
}

# All done with a transaction!
sub TransactionDone {
    # ARG0 = SOAP::Response object
    my ( $kernel, $heap, $response, $done_string, $done_detail ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];

	debug("<<<<<< BUILDING DONE >>>>>>>") if DEBUG;

    # Set up the response!
	$response->code( HTTP_OK );

	# Set Content-Type header
	$response->header( 'Content-Type', $heap->{CONTENTTYPE} );

	# Set default for short and detail
	$done_string = "Done" unless $done_string;
	$done_detail = "Sucessfully terminated your request" unless $done_detail;	

	# Build answer
	$response->content( build_response($done_string, $done_detail, $response->content) );

	debug("Done code: " . $response->code ) if DEBUG;
    debug("Done header: " . $response->headers->as_string ) if DEBUG;
    debug("Done content: " . Dumper($response->content) ) if DEBUG;

	# Marhsall the answer
	$response->content( marshall($response->content, $response->header('Content-Type')) );

    # Send it off!
    $kernel->post( $heap->{'ALIAS'} . '-BACKEND', 'DONE', $response );

    # Debug stuff
    if (DEBUG) {
		my $service = $response->restservice;
		my $method = $response->restmethod;
		my $ip = $response->connection->remote_ip();
        debug('Finished processing '.$_[STATE]." Service $service -> Method $method for $ip");
    }

	debug("Sent done: " . $response->content . "\n" ) if DEBUG;

    # All done!
    return;
}

# Close the transaction
sub TransactionClose {
	my ( $kernel, $heap, $response ) = @_[KERNEL, HEAP, ARG0];

    # Send it off to the backend, signaling CLOSE
    $kernel->post( $heap->{'ALIAS'} . '-BACKEND', 'CLOSE', $response );

    # Debug stuff
    if (DEBUG) {
        debug('Closing the socket of this Service '
          . $response->restmethod
          . ' -> Method '
          . $response->restmethod() . ' for '
          . $response->connection->remote_ip());
    }

    # All done!
    return;
}

1;
__END__

=head1 NAME

POE::Component::Server::REST - a solution kit for REST interfaces.

=head1 SHORT DESCRIPTION

POE::Component::Server::REST is a solution kit for REST interfaces.

	- Delegates requests to the appropriate hierarchic path's method.
	- Unmarshalls/marshalls from/to JSON/XML/YAML
	- Delivers request content as hashref to the appropriate method.
	- Delivers request keys as string to the appropriate method.

=head1 SYNOPSIS

	NOTE: The whole example can be found in the package's examples directory.

	use POE;
	sub POE::Component::Server::REST::DEBUG() { 1 };
	use POE::Component::Server::REST;
	use HTTP::Status qw(:constants);
	use Sys::Hostname;
	use Try::Tiny;

	# This is the POE..REST server
	my $service = 'restservice';
	POE::Component::Server::REST->new(
		'ALIAS'         => $service,
		'ADDRESS'       => '0.0.0.0',
		'PORT'          => 8081,
		'HOSTNAME'      => hostname(),
		'CONTENTTYPE'   => 'text/json',
	);

	# The URI paths mapped to events
	my $methods = {
		'_start'        =>  \&start,
		'_stop'         =>  \&stop,
		'GET/author'     =>  \&get_author,
		'GET/authors'    =>  \&get_authors,
		'GET/author/douglas/adams' => \&get_special,
		'POST/author'    =>  \&add_author,
		'PUT/author'     =>  \&upd_author,
		'DELETE/author'  =>  \&del_author,
	};

	# This is OUR session
	my $name = "library";
	POE::Session->create(
		'inline_states' => $methods
	);

	POE::Kernel->run;
	exit 0;

	sub get_author {
	    my ($kernel, $heap, $response, $key) = @_[KERNEL, HEAP, ARG0, ARG1];

		try {
			# Validate if the request was unmarshalled successfully.
			# Only needed if you are interested in the request body.
			my $body = $response->restbody;
			unless ( $body ) {
				$kernel->post( $service, 'FAULT', $response, HTTP_BAD_REQUEST, "Invalid Request", "Unable to parse your request."  );
				return;
			}

			# Accessing the requests unmarshalled content.
			# This option is optional, be sure to check hash-key  existance before accessing it.
			my $unpopular;
			if ( exists $body->{unpopular} ) {
				$unpopular = $body->{unpopular};
			}

			# If unpopular is true, we inform that we have none.
			if( $unpopular ) {
				$kernel->post( $service, 'FAULT', $response, HTTP_NOT_FOUND, "NotFound", "Sry I dont have any unpopular authors."  );
                return;
			}

			# Build answer
			my $answer = { 
				author => { 
					id => 1, 
					name => FooBar
				}
			};		
		
			# Set answer	
			$response->content($answer);
	
			# Done
			$kernel->post( $service, 'DONE', $response );
			return;
			
		} catch {
			$kernel->post( $service, 'FAULT', $response, HTTP_NOT_FOUND, "Error", $_  );
		};
	}

	sub get_authors { ... }
	sub get_special { ... }
	sub add_author { ... }
	sub upd_author { ... }
	sub del_author { ... }	
	
=head1 ABSTRACT

	A complete solution kit for REST interfaces.

=head1 DESCRIPTION

This module makes serving REST requests a breeze in POE.

The hardest thing to understand in this module is the REST Body. That's it!

The standard way to use this module is to do this:

	use POE;
	use POE::Component::Server::REST;

	POE::Component::Server::REST->new( ... );

	POE::Session->create( ... );

	POE::Kernel->run();

POE::Component::Server::REST is a bolt-on component that can publish event handlers via REST over HTTP. 
Currently, this module only supports JSON, XML or YAML requests. 
The HTTP server is done via POE::Component::Server::SimpleHTTP.

=head2  Starting Server::REST

To start Server::REST, just call it's new method:

	POE::Component::Server::REST->new(
		'ALIAS'         =>      'MyREST',
		'ADDRESS'       =>      '192.168.1.1',
		'PORT'          =>      11111,
		'HOSTNAME'      =>      'MySite.com',
		'HEADERS'       =>      {},
		'CONTENTTYPE'	=>		'text/json',
	);

This method will die on error or return success.

=over 4

=item C<ALIAS>

This will set the alias for the REST Service Session used in the POE Kernel. This
will default to "rest"

=item C<ADDRESS>

This value will be passed to POE::Component::Server::SimpleHTTP to bind to.

Examples: 
	ADDRESS => 0 # Bind to all addresses + localhost 
	ADDRESS => 'localhost' # Bind to localhost 
	ADDRESS => '192.168.1.1' # Bindto specified IP

=item C<PORT>

This value will be passed to POE::Component::Server::SimpleHTTP to bind to.

=item C<HOSTNAME>

This value is for the HTTP::Request's URI to point to. If this is
not supplied, POE::Component::Server::SimpleHTTP will use
Sys::Hostname to find it.

=item C<HEADERS>

This should be a hashref, that will become the default headers on
all HTTP::Response objects. You can override this in individual
requests by setting it via $response->header( ... )

The default header is: Server => "POE::Component::Server::REST/$VERSION"

For more information, consult the HTTP::Headers module.

=item C<CONTENTTYPE>

Defines in what format request and responses should be 
unmarshalled/marshalled. Current supported formats are: 

	text/json (DEFAULT_CONTENT)
	text/yaml 
	text/xml

Q: Why is JSON supported? I thought this is a pure JavaScript serializing language?
A: It's widely spread across web development communities, so alot of stable tools and libraries are available for it.
JSON is also the "part" of YAML which is actually used most and therefor the default. 

=item C<SIMPLEHTTP>

This allows you to pass options to the SimpleHTTP backend. One of the real reasons is to support SSL in Server::REST, yay! 
To learn how to use SSL, please consult the POE::Component::Server::SimpleHTTP documentation. 
Of course, you could totally screw up things, just use this with caution :)

You must pass a hash reference as the value, because it will be expanded and put in the Server::SimpleHTTP->new() constructor.

=back

=head2 Events

There are only a few ways to communicate with Server::REST.

=over 4

=item C<ADDMETHOD>

	This event accepts four arguments:
		- The intended session alias
		- The intended session event
		- The public service name       ( not required -> defaults to session alias )
		- The public method name        ( not required -> defaults to session event )

	Calling this event will add the method to the registry.
	NOTE: This will overwrite the old definition of a method if it exists!

=item C<DELMETHOD>

	This event accepts two arguments:
		- The service name
		- The method name

	Calling this event will remove the method from the registry.

	NOTE: if the service now contains no methods, it will also be removed.

=item C<DELSERVICE>

	This event accepts one argument:
		- The service name

	Calling this event will remove the entire service from the registry.

=item C<DONE>

	This event accepts only one argument: the REST::Response object we sent to the handler.

	Calling this event implies that this particular request is done, and will proceed to close the socket.

	NOTE: This method automatically sets some parameters:
		- HTTP Status = 200 ( if not defined )
		- HTTP Header value of 'Content-Type' = DEFAULT_CONTENT

	To get greater throughput and response time, do not post() to the DONE event, call() it!
	However, this will force your program to block while servicing REST requests...

=item C<FAULT>

	This event accepts five arguments:
		- the HTTP::Response object we sent to the handler
		- REST Fault Code       ( not required -> defaults to 500 )
		- REST Fault String     ( not required -> defaults to 'Fault' )
		- REST Fault Detail     ( not required -> defaults to 'Apllication faulted')
		- REST Fault Actor      ( not required -> defaults to undef)

	Again, calling this event implies that this particular request is done, and will proceed to close the socket.

	Calling this event will generate a REST Fault and return it to the client.

	NOTE: This method automatically sets some parameters:
		- HTTP Status = 500 ( if not defined )
		- HTTP Header value of 'Content-Type' = DEFAULT_CONTENT
		- HTTP Content = marshalled content of whatever type you have instantiated the server with. 

=item C<CLOSE>

	This event accepts only one argument: the REST::Response object we sent to the handler.

	Calling this event will proceed to close the socket, not sending any output.

=item C<STARTLISTEN>

	Starts the listening socket, if it was shut down

=item C<STOPLISTEN>

	Simply a wrapper for SHUTDOWN GRACEFUL, but will not shutdown Server::REST if there is no more requests

=item C<SHUTDOWN>

	Without arguments, Server::REST does this:
		Close the listening socket
		Kills all pending requests by closing their sockets
		Removes it's alias

	With an argument of 'GRACEFUL', Server::REST does this:
		Close the listening socket
		Waits for all pending requests to come in via DONE/FAULT/CLOSE, then removes it's alias

=back

=head2 Processing Requests

Ff you're new to the world of REST, reading RESTful documentation is recommended! 

Now, once you have set up the services/methods, what do you expect fromServer::REST? 
Every request is pretty straightforward, you just get a Server::REST::Response object in ARG0 and an optional KEY identifier in ARG1.

	The Server::REST::Response object contains a wealth of information about the specified request:
		- There is the SimpleHTTP::Connection object, which gives you connection information
		- There is the various REST accessors provided via Server::REST::Response
		- There is the HTTP::Request object

	Example information you can get:
		$response->connection->remote_ip()      # IP of the client
		$response->restrequest->uri()           # Original URI
		$response->restmethod()                 # The REST method that was called
		$response->restbody()                   # The unmarshalled request content, is undef if unmarshalling failed.

Simply experiment using Data::Dumper and you'll quickly get the hang of it!

When you're done with the REST request, stuff whatever output you have
into the content of the response object by passing it a HASH/ARRAY Reference.

	$response->content({ Foo => 1 });

IMPORTANT: I thought it might be smart to use a standard structure for all Responses. Your content ref
will be wrapped into a response structure like the following one:

	result => {
		short => $short_done_or_fault_msg,
		detail => $detail_done_or_fault_msg,
		content => $your_struct,
	}


The only thing left to do is send it off to the DONE event 
This struct is then beeing marshalled into whatever CONTENTTYPE you have specified.

	$kernel->post( 'MyREST', 'DONE', $response );
	OR
	$kernel->post( 'MyREST', 'DONE', $response, 'Done', 'Successfully terminated your request.' );

If there's an error, you can send it to the FAULT event, which will
convert it into a REST fault.

	$kernel->post( 'MyREST', 'FAULT', $response, 'Client.Authentication', 'Invalid password' );

=head2 Server::REST Notes

This module is very picky about capitalization and copy&paste errors! and was copied with the
authorization of the owner of POE::Component::Server::SOAP :) Thanks!

All of the options are uppercase, to avoid confusion.

You can enable debugging mode by doing this:

	sub POE::Component::Server::REST::DEBUG () { 1 }
	use POE::Component::Server::REST;

=head2 Using SSL

So you want to use SSL in Server::REST? Here's a example on how to do it:

	POE::Component::Server::REST->new(
		...
		'SIMPLEHTTP'    =>      {
				'SSLKEYCERT'    =>      [ 'public-key.pem', 'public-cert.pem' ],
		},
	);

	# And that's it provided you've already created the necessary key + certificate file :)
	# EXPERIMENTAL -> See SIMPLEHTTP

=head1 SUPPORT

    You can find documentation for this module with the perldoc command.

	perldoc POE::Component::Server::REST

=head2 Websites

=over 4

=item    *   AnnoCPAN: Annotated CPAN documentation

	http://annocpan.org/dist/POE-Component-Server-REST

=item    *   CPAN Ratings

	http://cpanratings.perl.org/d/POE-Component-Server-REST

=item    *   RT: CPAN's request tracker

	http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-Server-REST

=item    *   Search CPAN

	http://search.cpan.org/dist/POE-Component-Server-REST

=back

=head2  Bugs

    Please report any bugs or feature requests to "bug-poe-component-server-rest at rt.cpan.org", or through the web
    interface at http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE-Component-Server-REST
    I will be notified, and then you'll automatically be notified of progress on your bug as I make changes.

=head1 SEE ALSO
    The examples directory that came with this component.

    POE

    HTTP::Response

    HTTP::Request

    POE::Component::Server::REST::Response

    POE::Component::Server::SimpleHTTP

    XML::Simple

	YAML::Tiny

    POE::Component::SSLify

=head1 AUTHOR

    Jstebens <jstebens@cpan.org>

    I used POE::Server::Component::SOAP as base for this module and documentation.
	There may be still POE::Server::Component::SOAP artifacts spread throught the
	documentation and code. If you find those, please let me know.

	Many thanks to Larwan "Apocalypse" Berke for the approval to use his code as base!

=head1 COPYRIGHT AND LICENSE

    Copyright 2011 by Jstebens

    This library is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.

=cut
