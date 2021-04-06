requires 'Mojolicious';
requires 'Net::EPP::Client';
requires 'XML::Twig';
requires 'Benchmark';
requires 'Net::IP';
requires 'Mojolicious::Plugin::AssetPack';
requires 'CSS::Minifier::XS';
requires 'JavaScript::Minifier::XS';
requires 'Mozilla::CA';
requires 'IO::Socket::SSL', '1.94';
requires 'CPAN::Meta::YAML', '0.011';
requires 'TAP::Harness', '3.29';
requires 'Syntax::Keyword::Try', '0.18';
on test => sub {
	requires 'Perl::Critic';
	requires 'Test::Perl::Critic';
};
