package POE::Component::Server::REST::Response;

use strict; 
use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '1.02';

# Set our stuff to SimpleHTTP::Response
use base qw( POE::Component::Server::SimpleHTTP::Response );

# Accessor for REST Service name
sub restservice {
      return shift->{'RESTSERVICE'};
}

# Accessor for REST Method name
sub restmethod {
      return shift->{'RESTMETHOD'};
}

# Accessor for REST Headers
sub restheaders {
      return shift->{'RESTHEADERS'};
}

# Accessor for REST Body
sub restbody {
      return shift->{'RESTBODY'};
}

# Accessor for REST URI
sub resturi {
      return shift->{'RESTURI'};
}

# Accessor for the original HTTP::Request object
sub restrequest {
      return shift->{'RESTREQUEST'};
}

