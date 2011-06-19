# Build.PL
use strict; use warnings;

use Module::Build;
my $build = Module::Build->new(
	# look up Module::Build::API for the info!
	'dynamic_config'	=> 0,
	'module_name'	=> 'POE::Component::Server::REST',
	'license'		=> 'perl',

	'dist_abstract'	=> 'Simple REST Server which allows binding REST API calls to POE-events.',

	'create_packlist'		=> 1,
	'create_makefile_pl'	=> 'traditional',
	'create_readme'		=> 1,

	'test_files'		=> 't/*.t',

	'add_to_cleanup'	=> [ 'META.yml', 'Makefile.PL', 'README', 'Makefile' ],	# automatically generated

	'requires'		=> {
		'POE'				=> 0,
		'POE::Component::Server::SimpleHTTP'	=> '1.54',	
		'XML::Simple'		=> '2.18',
		'YAML::Tiny'		=> '1.32',
		'JSON' => '2.21',
		'URI::Split' => '1.35',
		'HTTP::Status' => '5.805',
		'POE::Session'		=> 0,
		'Carp'		=> 0,
		'perl'		=> '5.006',
	},
);

# all done!
$build->create_build_script;
