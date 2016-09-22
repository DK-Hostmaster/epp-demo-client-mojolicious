requires 'Mojolicious';
requires 'Net::EPP::Client';
requires 'XML::Twig';
requires 'TryCatch';
requires 'Benchmark';
requires 'Net::IP';
requires 'Mojolicious::Plugin::AssetPack';
requires 'CSS::Minifier::XS';
requires 'JavaScript::Minifier::XS';
requires 'Mozilla::CA';
requires 'IO::Socket::SSL', '1.94';

on test => sub {
	requires 'Perl::Critic';
	requires 'Test::Perl::Critic';
};
