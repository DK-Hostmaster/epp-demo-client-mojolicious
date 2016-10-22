![screenshot](images/main-screen.png)

<!-- MarkdownTOC -->

- [NAME](#name)
- [VERSION](#version)
- [USAGE](#usage)
    - [Using `docker`](#using-docker)
- [ABOUT](#about)
- [DEPENDENCIES](#dependencies)
- [SEE ALSO](#see-also)
- [Changes](#changes)
    - [1.1.0 feature release](#110-feature-release)
    - [1.0.1 bug fix release](#101-bug-fix-release)
    - [1.0.0 initial release](#100-initial-release)
- [COPYRIGHT](#copyright)
- [LICENSE](#license)

<!-- /MarkdownTOC -->

<a name="name"></a>
# NAME

DK Hostmaster EPP service demo/test client

<a name="version"></a>
# VERSION

This documentation describes version 1.1.0

<a name="usage"></a>
# USAGE

    $ morbo -l https://*:3000 client.pl

Open your browser at:

    https://127.0.0.1:3000/

<a name="using-docker"></a>
## Using `docker`

The application can be used using `docker`

    $ docker build -t epp-demo-client .

    $ docker run --rm -p 3000:3000 epp-demo-client

Open your browser at:

    https://localhost:3000/


<a name="about"></a>
# ABOUT

This client was developed to assist our testers in testing our own EPP service. As for other services we have previously released clients as open source under a MIT license to provide a springboard for users/developers wanting to get started with our services.

<a name="dependencies"></a>
# DEPENDENCIES

This client is implemented using Mojolicious in addition the following
Perl modules are used and all are available from CPAN.

- [Mojolicious](https://metacpan.org/pod/Mojolicious)
- [Net::EPP::Client](https://metacpan.org/pod/Net::EPP::Client)
- [XML::Twig](https://metacpan.org/pod/XML::Twig)
- [TryCatch](https://metacpan.org/pod/TryCatch)
- [Benchmark](https://metacpan.org/pod/Benchmark)
- [Net::IP](https://metacpan.org/pod/Net::IP)
- [Mojolicious::Plugin::AssetPack](https://metacpan.org/pod/Mojolicious::Plugin::AssetPack)
- [CSS::Minifier::XS](https://metacpan.org/pod/CSS::Minifier::XS)
- [JavaScript::Minifier::XS](https://metacpan.org/pod/Javascript::Minifier::XS)
- [Mozilla::CA](https://metacpan.org/pod/Mozilla::CA)
- [IO::Socket::SSL 1.94](https://metacpan.org/pod/IO::Socket::SSL)

In addition to the above Perl modules, the client uses [Twitter Bootstrap](http://getbootstrap.com/) and hereby jQuery. These are automatically downloaded via CDNs and are not distributed with the client software.

<a name="see-also"></a>
# SEE ALSO

For information on the service, please refer to [the specification](https://github.com/DK-Hostmaster/epp-service-specification) from DK Hostmaster or [the service page with DK Hostmaster](https://www.dk-hostmaster.dk/en/epp).

The main site for this client is the Github repository.

- The client repository: https://github.com/DK-Hostmaster/epp-demo-client-mojolicious
- The EPP service specification: https://github.com/DK-Hostmaster/epp-service-specification
- Thee EPP service page with DK Hostmaster A/S: https://www.dk-hostmaster.dk/en/epp

<a name="changes"></a>
# Changes

<a name="110-feature-release"></a>
## 1.1.0 feature release

- Prettifying XML outputted to log for readability

<a name="101-bug-fix-release"></a>
## 1.0.1 bug fix release

- Several bug fixes and adjustments based on inputs from our testers

<a name="100-initial-release"></a>
## 1.0.0 initial release

- Initial version

<a name="copyright"></a>
# COPYRIGHT

This software is under copyright by DK Hostmaster A/S 2016

<a name="license"></a>
# LICENSE

This software is licensed under the MIT software license

Please refer to the LICENSE file accompanying this file.
