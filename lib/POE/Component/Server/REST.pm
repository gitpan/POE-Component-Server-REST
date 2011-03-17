package POE::Component::Server::REST;

use strict; 
use warnings;

use vars qw( $VERSION );
$VERSION = '!.00';

use Carp qw(croak);

# Import the proper POE stuff
use POE;
use POE::Session;
use POE::Component::Server::SimpleHTTP;
use Data::Dumper;
use XML::Simple;

# Our own modules
use POE::Component::Server::REST::Response;

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
};

# Set some constants
BEGIN {
      if ( ! defined &DEBUG ) { *DEBUG = sub () { 2 } }
}

sub new {
      # Get the OOP's type
      my $type = shift;

      # Sanity checking
      if ( @_ & 1 ) {
            croak( 'POE::Component::Server::REST->new needs even number of options' );
      }

      # The options hash
      my %opt = @_;

      # Our own options
      my ( $ALIAS, $ADDRESS, $PORT, $HEADERS, $HOSTNAME, $MUSTUNDERSTAND, $SIMPLEHTTP );

      # You could say I should do this: $Stuff = delete $opt{'Stuff'}
      # But, that kind of behavior is not defined, so I would not trust it...

      # Get the session alias
      if ( exists $opt{'ALIAS'} and defined $opt{'ALIAS'} and length( $opt{'ALIAS'} ) ) {
            $ALIAS = $opt{'ALIAS'};
            delete $opt{'ALIAS'};
      } else {
            # Debugging info...
            if ( DEBUG ) {
                  warn 'Using default ALIAS = RESTService';
            }

            # Set the default
            $ALIAS = 'RESTService';

            # Remove any lingering ALIAS
            if ( exists $opt{'ALIAS'} ) {
                  delete $opt{'ALIAS'};
            }
      }

	# Get the PORT
      if ( exists $opt{'PORT'} and defined $opt{'PORT'} and length( $opt{'PORT'} ) ) {
            $PORT = $opt{'PORT'};
            delete $opt{'PORT'};
      } else {
            # Debugging info...
            if ( DEBUG ) {
                  warn 'Using default PORT = 80';
            }

            # Set the default
            $PORT = 80;

            # Remove any lingering PORT
            if ( exists $opt{'PORT'} ) {
                  delete $opt{'PORT'};
            }
      }

      # Get the ADDRESS
      if ( exists $opt{'ADDRESS'} and defined $opt{'ADDRESS'} and length( $opt{'ADDRESS'} ) ) {
            $ADDRESS = $opt{'ADDRESS'};
            delete $opt{'ADDRESS'};
      } else {
            croak( 'ADDRESS is required to create a new POE::Component::Server::REST instance!' );
      }

      # Get the HEADERS
      if ( exists $opt{'HEADERS'} and defined $opt{'HEADERS'} ) {
            # Make sure it is ref to hash
            if ( ref $opt{'HEADERS'} and ref( $opt{'HEADERS'} ) eq 'HASH' ) {
                  $HEADERS = $opt{'HEADERS'};
                  delete $opt{'HEADERS'};
            } else {
                  croak( 'HEADERS must be a reference to a HASH!' );
            }
      } else {
            # Debugging info...
            if ( DEBUG ) {
                  warn 'Using default HEADERS ( SERVER => POE::Component::Server::REST/' . $VERSION . ' )';
            }

            # Set the default
            $HEADERS = {
                  'Server'    =>    'POE::Component::Server::REST/' . $VERSION,
            };

            # Remove any lingering HEADERS
            if ( exists $opt{'HEADERS'} ) {
                  delete $opt{'HEADERS'};
            }
      }

	# Get the HOSTNAME
      if ( exists $opt{'HOSTNAME'} and defined $opt{'HOSTNAME'} and length( $opt{'HOSTNAME'} ) ) {
            $HOSTNAME = $opt{'HOSTNAME'};
            delete $opt{'HOSTNAME'};
      } else {
            # Debugging info...
            if ( DEBUG ) {
                  warn 'Letting POE::Component::Server::SimpleHTTP create a default HOSTNAME';
            }

            # Set the default
            $HOSTNAME = undef;

            # Remove any lingering HOSTNAME
            if ( exists $opt{'HOSTNAME'} ) {
                  delete $opt{'HOSTNAME'};
            }
      }

      # Get the MUSTUNDERSTAND
      if ( exists $opt{'MUSTUNDERSTAND'} and defined $opt{'MUSTUNDERSTAND'} and length( $opt{'MUSTUNDERSTAND'} ) ) {
            $MUSTUNDERSTAND = $opt{'MUSTUNDERSTAND'};
            delete $opt{'MUSTUNDERSTAND'};
      } else {
            # Debugging info...
            if ( DEBUG ) {
                  warn 'Using default MUSTUNDERSTAND ( 1 )';
            }

            # Set the default
            $MUSTUNDERSTAND = 1;

            # Remove any lingering MUSTUNDERSTAND
            if ( exists $opt{'MUSTUNDERSTAND'} ) {
                  delete $opt{'MUSTUNDERSTAND'};
            }
      }

      # Get the SIMPLEHTTP
      if ( exists $opt{'SIMPLEHTTP'} and defined $opt{'SIMPLEHTTP'} and ref( $opt{'SIMPLEHTTP'} ) eq 'HASH' ) {
            $SIMPLEHTTP = $opt{'SIMPLEHTTP'};
            delete $opt{'SIMPLEHTTP'};
      }

      # Anything left over is unrecognized
      if ( DEBUG ) {
            if ( keys %opt > 0 ) {
                  croak( 'Unrecognized options were present in POE::Component::Server::REST->new -> ' . join( ', ', keys %opt ) );
            }
      }

      # Create the POE Session!
      POE::Session->create(
            'inline_states'   =>    {
                  # Generic stuff
                  '_start'    	=>    \&StartServer,
                  '_stop'           =>    sub {},
                  '_child'    	=>    \&SmartShutdown,

                  # Shuts down the server
                  'SHUTDOWN'  	=>    \&StopServer,
                  'STOPLISTEN'      =>    \&StopListen,
                  'STARTLISTEN'     =>    \&StartListen,

                  # Adds/deletes Methods
                  'ADDMETHOD' 	=>    \&AddMethod,
                  'DELMETHOD' 	=>    \&DeleteMethod,
                  'DELSERVICE'      =>    \&DeleteService,

                  # Transaction handlers
                  'Got_Request'     =>    \&TransactionStart,
                  'FAULT'           =>    \&TransactionFault,
                  'RAWFAULT'  	=>    \&TransactionFault,
                  'DONE'            =>    \&TransactionDone,
                  'RAWDONE'   	=>    \&TransactionDone,
                  'CLOSE'           =>    \&TransactionClose,
            },

            # Our own heap
            'heap'            =>    {
                  'INTERFACES'      =>    {},
                  'ALIAS'           =>    $ALIAS,
                  'ADDRESS'         =>    $ADDRESS,
                  'PORT'            =>    $PORT,
                  'HEADERS'         =>    $HEADERS,
                  'HOSTNAME'        =>    $HOSTNAME,
                  'MUSTUNDERSTAND'  =>    $MUSTUNDERSTAND,
                  'SIMPLEHTTP'      =>    $SIMPLEHTTP,
            },
      ) or die 'Unable to create a new session!';

      # Return success
      return 1;
}

# Creates the server
sub StartServer {
      # Set the alias
      $_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} );

      # Create the webserver!
      POE::Component::Server::SimpleHTTP->new(
            'ALIAS'         =>      $_[HEAP]->{'ALIAS'} . '-BACKEND',
            'ADDRESS'       =>      $_[HEAP]->{'ADDRESS'},
            'PORT'          =>      $_[HEAP]->{'PORT'},
            'HOSTNAME'      =>      $_[HEAP]->{'HOSTNAME'},
            'HEADERS'   =>    $_[HEAP]->{'HEADERS'},
            'HANDLERS'      =>      [
                  {
                        'DIR'           =>      '.*',
                        'SESSION'       =>      $_[HEAP]->{'ALIAS'},
                        'EVENT'         =>      'Got_Request',
                  },
            ],
            ( defined $_[HEAP]->{'SIMPLEHTTP'} ? ( %{ $_[HEAP]->{'SIMPLEHTTP'} } ) : () ),
      ) or die 'Unable to create the HTTP Server';

      # Success!
      return;
}

# Shuts down the server
sub StopServer {
      # Tell the webserver to die!
      if ( defined $_[ARG0] and $_[ARG0] eq 'GRACEFUL' ) {
            # Shutdown gently...
            $_[KERNEL]->call( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'SHUTDOWN', 'GRACEFUL' );
      } else {
            # Shutdown NOW!
            $_[KERNEL]->call( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'SHUTDOWN' );
      }

      # Success!
      return;
}

# Stops listening for connections
sub StopListen {
      # Tell the webserver this!
      $_[KERNEL]->call( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'STOPLISTEN' );

      # Success!
      return;
}

# Starts listening for connections
sub StartListen {
      # Tell the webserver this!
      $_[KERNEL]->call( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'STARTLISTEN' );

      # Success!
      return;
}

# Watches for SimpleHTTP shutting down and shuts down ourself
sub SmartShutdown {
      # ARG0 = type, ARG1 = ref to session, ARG2 = parameters

      # Check for real shutdown
      if ( $_[ARG0] eq 'lose' ) {
            # Remove our alias
            $_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

            # Debug stuff
            if ( DEBUG ) {
                  warn 'Received _child event from SimpleHTTP, shutting down';
            }
      }

      # All done!
      return;
}

# Adds a method
sub AddMethod {
      # ARG0: Session alias, ARG1: Session event, ARG2: Service name, ARG3: Method name
      my( $alias, $event, $service, $method );

      # Check for stuff!
      if ( defined $_[ARG0] and length( $_[ARG0] ) ) {
            $alias = $_[ARG0];
      } else {
            # Complain!
            if ( DEBUG ) {
                  warn 'Did not get a Session Alias';
            }
            return;
      }

      if ( defined $_[ARG1] and length( $_[ARG1] ) ) {
            $event = $_[ARG1];
      } else {
            # Complain!
            if ( DEBUG ) {
                  warn 'Did not get a Session Event';
            }
            return;
      }

      # If none, defaults to the Session stuff
      if ( defined $_[ARG2] and length( $_[ARG2] ) ) {
            $service = $_[ARG2];
      } else {
            # Debugging stuff
            if ( DEBUG ) {
                  warn 'Using Session Alias as Service Name';
            }

            $service = $alias;
      }

      if ( defined $_[ARG3] and length( $_[ARG3] ) ) {
            $method = $_[ARG3];
      } else {
            # Debugging stuff
            if ( DEBUG ) {
                  warn 'Using Session Event as Method Name';
            }

            $method = $event;
      }

      # If we are debugging, check if we overwrote another method
      if ( DEBUG ) {
            if ( exists $_[HEAP]->{'INTERFACES'}->{ $service } ) {
                  if ( exists $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } ) {
                        warn 'Overwriting old method entry in the registry ( ' . $service . ' -> ' . $method . ' )';
                  }
            }
      }

      # Add it to our INTERFACES
      $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } = [ $alias, $event ];

      # Return success
      return 1;
}

# Deletes a method
sub DeleteMethod {
      # ARG0: Service name, ARG1: Service method name
      my( $service, $method ) = @_[ ARG0, ARG1 ];

      # Validation
      if ( defined $service and length( $service ) ) {
            # Validation
            if ( defined $method and length( $method ) ) {
                  # Validation
                  if ( exists $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } ) {
                        # Delete it!
                        delete $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method };

                        # Check to see if the service now have no methods
                        if ( keys( %{ $_[HEAP]->{'INTERFACES'}->{ $service } } ) == 0 ) {
                              # Debug stuff
                              if ( DEBUG ) {
                                    warn "Service $service contains no methods, removing it!";
                              }

                              # Delete it!
                              delete $_[HEAP]->{'INTERFACES'}->{ $service };
                        }

                        # Return success
                        return 1;
                  } else {
                        # Error!
                        if ( DEBUG ) {
                              warn 'Tried to delete a nonexistant Method in Service -> ' . $service . ' : ' . $method;
                        }
                  }
            } else {
                  # Complain!
                  if ( DEBUG ) {
                        warn 'Did not get a method to delete in Service -> ' . $service;
                  }
            }
      } else {
            # No arguments!
            if ( DEBUG ) {
                  warn 'Received no arguments!';
            }
      }

      return;
}

# Deletes a service
sub DeleteService {
      # ARG0: Service name
      my( $service ) = $_[ ARG0 ];

      # Validation
      if ( defined $service and length( $service ) ) {
            # Validation
            if ( exists $_[HEAP]->{'INTERFACES'}->{ $service } ) {
                  # Delete it!
                  delete $_[HEAP]->{'INTERFACES'}->{ $service };

                  # Return success!
                  return 1;
            } else {
                  # Error!
                  if ( DEBUG ) {
                        warn 'Tried to delete a Service that does not exist! -> ' . $service;
                  }
            }
      } else {
            # No arguments!
            if ( DEBUG ) {
                  warn 'Received no arguments!';
            }
      }

      return;
}

# Got a request, handle it!
sub TransactionStart {
      # ARG0 = HTTP::Request, ARG1 = HTTP::Response, ARG2 = dir that matched
      my ( $request, $response ) = @_[ ARG0, ARG1 ];

      # Check for error in parsing of request
      if ( ! defined $request ) {
            # Create a new error and send it off!
            $_[KERNEL]->yield( 'FAULT',
                  $response,
                  CLIENT_BADREQUEST,
                  'Bad Request',
                  'Unable to parse HTTP query',
            );
            return;
      }

      # We only handle text/xml content
	warn("DEBUG: received header: ". $request->header('Content-Type')) if DEBUG;
      if ( ! $request->header('Content-Type') || $request->header('Content-Type') !~ /^text\/xml(;.*)?$/ ) {
            # Create a new error and send it off!
            $_[KERNEL]->yield( 'FAULT',
                  $response,
                  CLIENT_BADREQUEST,
                  'Bad Request',
                  'Content-Type must be text/xml',
            );
            return;
      }

      # We need the method name
	my $type = $request->method();
	warn("DEBUG: Request is of method: ".uc($type)) if DEBUG;
      if ( ! defined $type or ! length( $type ) ) {
            # Create a new error and send it off!
            $_[KERNEL]->yield( 'FAULT',
                  $response,
                  CLIENT_BADREQUEST,
                  'Bad Request',
                  'Invalid Request Method',
            );
            return;
      }

      # Get some stuff
	my $service;
      my $query_string = $request->uri->query();
      if ( ! defined $query_string or $query_string !~ /\bsession=(.+ $ )/x ) {

		# Set service when there is only one service known.
		my @services = keys %{ $_[HEAP]->{'INTERFACES'}  };
		if( scalar(@services) == 1 ) {
			$service = $services[0];
			warn("DEBUG: Only one service known, guess its that one.") if DEBUG;
		} else {
			# Create a new error and send it off!
			warn("DEBUG: too many services to guess the right one: ". join(",", @services)) if DEBUG;
			$_[KERNEL]->yield( 'FAULT',
				$response,
				CLIENT_BADREQUEST,
				'Bad Request',
				'Unable to parse the URI for the service',
			);
			return;
		}
      } else {
		# Set the service
		$service = $1;
	}

      # Check to see if this service exists
      if ( ! exists $_[HEAP]->{'INTERFACES'}->{ $service } ) {
            # Create a new error and send it off!
            $_[KERNEL]->yield( 'FAULT',
                  $response,
                  CLIENT_BADREQUEST,
                  'Bad Request',
                  "Unknown service: $service",
            );
            return;
      } else {
		warn("DEBUG: Found service $service to be valid.");	
	}

      # Get the method name
	my $uri = $request->uri;
	warn("DEBUG: requested uri: $uri");
	if ( $uri !~ /(\/\D+)(\/\w+)?(\/)?(\?session=(.+))?$/ ) {
            # Create a new error and send it off!
            $_[KERNEL]->yield( 'FAULT',
                  $response,
                  CLIENT_BADREQUEST,
                  'Bad Request',
                  "Unrecognized REST url structure: $uri",
            );
            return;
      }

	# Get the uri + method
      my $method = $1 || '';
      my $restkey = $2 || '';

	# Remove trailing slash
	$method =~ s/\/$//;
	$restkey =~ s/^\///;

	# Add prefx with given HTTP request method eg. PUT/foo/baz/bar
	$method = "$type$method";

      # Check to see if this method exists
      if ( ! exists $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } ) {
            # Create a new error and send it off!
            $_[KERNEL]->yield( 'FAULT',
                  $response,
                  CLIENT_BADREQUEST,
                  'Bad Request',
                  "Unknown method: $method (Available: ".join(",", keys %{ $_[HEAP]->{'INTERFACES'}->{ $service } }).")",
            );
            return;
      }

      # Check for errors
      if ( $@ ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'FAULT',
			$response,
			SERVER_INTERNALERROR,
			'Application Faulted',
			"Some errors occured while processing the request: $@",
		);

            # All done!
            return;
      }

	# Check the headers for the mustUnderstand attribute, and Fault if it is present
      my $head_count = 1;
      my @headers = ();

      # Extract the body
      my $body = $request->content;

      # If it is an empty string, turn it into undef
      if ( defined $body and ! ref( $body ) and $body eq '' ) {
            $body = undef;
      }

	# Parse it
	if ( defined($body) ) {
		my $struct = eval { XMLin($body, KeepRoot => 1 ) };
		if($@) {
			$_[KERNEL]->yield( 'FAULT',
				$response,
				CLIENT_BADREQUEST,
				'Bad Request',
				"Error parsing XML structure.",
			);
			return;
		}	
		$response->content( $struct );
	} 

      # Hax0r the Response to include our stuff!
      $response->{'RESTMETHOD'} = $method;
      $response->{'RESTBODY'} = $body;
      $response->{'RESTSERVICE'} = $service;
      $response->{'RESTREQUEST'} = $request;
      $response->{'RESTURI'} = $method;

      # Make the headers undef if there is none
      if ( scalar( @headers ) ) {
            $response->{'RESTHEADERS'} = \@headers;
      } else {
            $response->{'RESTHEADERS'} = undef;
      }

      # ReBless it ;)
      bless( $response, 'POE::Component::Server::REST::Response' );

      # Send it off to the handler!
      $_[KERNEL]->post( $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method }->[0],
            $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method }->[1],
            $response,
		$restkey,
      );

      # Debugging stuff
      if ( DEBUG ) {
            warn "Sending off to the handler: Service $service -> Method $method for " . $response->connection->remote_ip();
      }

      if ( DEBUG == 2 ) {
            print STDERR $request->content(), "\n\n";
      }

      # All done!
      return;
}


# Creates the fault and sends it off
sub TransactionFault {
      # ARG0 = SOAP::Response, ARG1 = SOAP faultcode, ARG2 = SOAP faultstring, ARG3 = SOAP Fault Detail, ARG4 = SOAP Fault Actor
      my ( $response, $fault_code, $fault_string, $fault_detail, $fault_actor ) = @_[ ARG0 .. ARG4 ];

      # Make sure we have a REST::Response object here :)
      if ( ! defined $response ) {
            # Debug stuff
            if ( DEBUG ) {
                  warn 'Received FAULT event but no arguments!';
            }
		$response = POE::Component::Server::REST::Response->new();
            #return;
      }

      # Is this a RAWFAULT event?
      my $content = undef;
      if ( $_[STATE] eq 'RAWFAULT' ) {
            $content = $response->content();
      } else {
            # Fault Code must be defined
            if ( ! defined $fault_code or ! length( $fault_code ) ) {
                  # Debug stuff
                  if ( DEBUG ) {
                        warn 'Setting default Fault Code';
                  }

                  # Set the default
                  $fault_code = SERVER_INTERNALERROR;
            }

            # FaultString is a short description of the error
            if ( ! defined $fault_string or ! length( $fault_string ) ) {
                  # Debug stuff
                  if ( DEBUG ) {
                        warn 'Setting default Fault String';
                  }

                  # Set the default
                  $fault_string = 'Application Faulted';
            }

            $content = XMLout({
			result => {
				short => [ $fault_string ],
				detail => [ $fault_detail ],
			},
		}, KeepRoot => 1, XMLDecl => 1 );
      }
	
	$response->code( $fault_code );
      $response->content( $content );

      # Setup the response
      if ( ! defined $response->code ) {
            $response->code( SERVER_INTERNALERROR );
      }

      $response->header( 'Content-Type', 'text/xml' );

      # Send it off to the backend!
      $_[KERNEL]->post( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'DONE', $response );

      # Debugging stuff
      if ( DEBUG ) {
            warn 'Finished processing ' . $_[STATE] . ' for ' . $response->connection->remote_ip();
      }

      if ( DEBUG == 2 ) {
            print STDERR "$content\n\n";
      }

      # All done!
      return;
}


# All done with a transaction!
sub TransactionDone {
      # ARG0 = SOAP::Response object
      my ($response, $done_string, $done_detail) = @_[ARG0, ARG1, ARG2];

      # Set up the response!
      if ( ! defined $response->code ) {
            $response->code( APP_OK );
      }
      $response->header( 'Content-Type', 'text/xml' );

	my $content;
      if ( $_[STATE] eq 'RAWDONE' ) {
            $content = $response->content();
      } else {
		my $struct = {
                  result => {
                        short => [ $done_string ],
                        detail => [ $done_detail ],
                  },
            };
		# Only set the content field if its defined.
		if( defined($response->content) && length($response->content) ) {
			$struct->{result}->{content} = [ $response->content ]; 
		}
		$content = XMLout( $struct , KeepRoot => 1, XMLDecl => 1);

	}
	$response->content($content);

      # Send it off!
      $_[KERNEL]->post( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'DONE', $response );

      # Debug stuff
      if ( DEBUG ) {
            warn 'Finished processing ' . $_[STATE] . ' Service ' . $response->restservice . ' -> Method ' . $response->restmethod . ' for ' . $response->connection->remote_ip();
      }

      if ( DEBUG == 2 ) {
            warn("DEBUG: ".$response->content."\n");
      }

      # All done!
      return;
}


# Close the transaction
sub TransactionClose {
      # ARG0 = SOAP::Response object
      my $response = $_[ARG0];

      # Send it off to the backend, signaling CLOSE
      $_[KERNEL]->post( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'CLOSE', $response );

      # Debug stuff
      if ( DEBUG ) {
            warn 'Closing the socket of this Service ' . $response->restmethod . ' -> Method ' . $response->restmethod() . ' for ' . $response->connection->remote_ip();
      }

      # All done!
      return;
}

