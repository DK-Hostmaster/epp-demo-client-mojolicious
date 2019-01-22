package EppDemoClient;
use Mojo::Base 'Mojolicious';

use Net::EPP::Client;
use Net::EPP::Frame::ObjectSpec;
use Net::EPP::Frame::Command;
use Net::EPP::Frame::Command::Login;
use Net::EPP::Frame::Command::Logout;
use Net::EPP::Frame::Command::Check::Host;
use Net::EPP::Frame::Command::Create::Host;
use Net::EPP::Frame::Command::Delete::Host;
use Net::EPP::Frame::Command::Info::Host;
use Net::EPP::Frame::Command::Update::Host;
use Net::EPP::Frame::Command::Check::Domain;
use Net::EPP::Frame::Command::Create::Domain;
use Net::EPP::Frame::Command::Info::Domain;
use Net::EPP::Frame::Command::Renew::Domain;
use Net::EPP::Frame::Command::Update::Domain;
use Net::EPP::Frame::Command::Poll::Req;
use Net::EPP::Frame::Command::Poll::Ack;

use Net::IP;
use Time::HiRes;
use Digest::MD5 qw(md5_hex);
use XML::Twig;
use TryCatch;

# This method will run once at server start
sub startup {
    my $self = shift;

    my $config = $self->plugin('Config');

    # Router
    my $r = $self->routes;

    $self->secrets(['VeryVerySecretSecret01234']);
    $self->sessions->default_expiration(0);

    $self->plugin(AssetPack => {pipes => [qw(Css JavaScript Combine)]});

    $self->asset->process(
        "app.css" => (
            "https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.css",
            "https://maxcdn.bootstrapcdn.com/font-awesome/4.6.3/css/font-awesome.css",
            "prism.css",
        )
    );

    $self->asset->process(
        "app.js" => (
            "https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.js",
            "https://netdna.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.js",
            "prism.js",
            "app.js",
        )
    );

    $self->helper(get_login_request => sub {
        my ($self, $username, $password) = @_;

        my $login = Net::EPP::Frame::Command::Login->new;

        $login->clID->appendText($username);
        $login->pw->appendText($password);
        $login->lang->appendText(    'en'  );
        $login->version->appendText( '1.0' );
        $login->clTRID->appendText( md5_hex(Time::HiRes::time().$$) ); # set the client transaction ID:
        foreach my $v (qw(domain host contact)){
            my $obj = $login->createElement('objURI');
            $obj->appendText($_) foreach Net::EPP::Frame::ObjectSpec->spec($v);
            $login->svcs->appendChild($obj);
        }

        return $login;
    });

    $self->helper(get_request_frame => sub {
        my ($self) = @_;

        my $object  = $self->param('object');
        my $command = $self->param('command');

        my $frame_name = 'Net::EPP::Frame::Command::' . ucfirst($command) . '::' . ucfirst($object);
        if($object eq 'poll') {
            if($command eq 'req') {
                $frame_name = 'Net::EPP::Frame::Command::Poll::Req';
            } else {
                $frame_name = 'Net::EPP::Frame::Command::Poll::Ack';
            }
        }

        my $frame = $frame_name->new;

        $self->app->log->info("Frame is $frame");

        my $domain = $self->param('domain');
        if ( not $domain) {
        } elsif ( UNIVERSAL::can($frame, 'setDomain') ) {
            $frame->setDomain($domain);
            $self->session(domain => $domain);
        } elsif ( UNIVERSAL::can($frame, 'addDomain') ) {
            $frame->addDomain($domain);
            $self->session(domain => $domain);
        }

        if($object eq 'domain' && $command eq 'renew') {
            my $period = $self->param('period');
            my $expire_date = $self->param('curExpDate');
            $frame->setCurExpDate($expire_date);
            $frame->setPeriod($period);
            $self->session(period => $period);
            $self->session(curExpDate => $expire_date);
        }

        my($domain_create_el) = $frame->getElementsByTagName('domain:create');
        if( $domain_create_el ) {
            my $period = $self->param('period');
            if ($period) {
                my $el = $frame->createElement('domain:period');
                $el->appendText($period);
                $el->setAttribute( 'unit', 'y' );
                $domain_create_el->appendChild($el);
            }

            my $nameserver_names     = $self->every_param('new_nameserver_name');
            my $nameserver_el = $frame->createElement('domain:ns');
            foreach my $nameserver_name ( @$nameserver_names ) {
                next unless $nameserver_name;
                my $el = $frame->createElement('domain:hostObj');
                $el->appendText($nameserver_name);
                $nameserver_el->appendChild($el);
            }
            $domain_create_el->appendChild($nameserver_el);

            my $registrant = $self->param('new_registrant');
            if ($registrant) {
                my $el = $frame->createElement('domain:registrant');
                $el->appendText($registrant);
                $domain_create_el->appendChild($el);
            }

            my $contact_types      = $self->every_param('new_contact_type');
            my $contact_userids    = $self->every_param('new_contact_userid');
            while ( @$contact_types ) {
                my $contact_type      = shift @$contact_types;
                my $contact_userid    = shift @$contact_userids;
                next unless $contact_type || $contact_userid;

                my $el = $frame->createElement('domain:contact');
                $el->appendText($contact_userid);
                $el->setAttribute( 'type', $contact_type );
                $domain_create_el->appendChild($el);
            }

            my $authinfo_pw = $self->param('authinfo_pw');
            if ($authinfo_pw) {
                my $authinfo_el = $frame->createElement('domain:authInfo');
                my $el = $frame->createElement('domain:pw');
                $el->appendText($authinfo_pw);
                $authinfo_el->appendChild($el);
                $domain_create_el->appendChild($authinfo_el);
            }

            my $keytags      = $self->every_param('new_ds_keytag');
            my $algorithms   = $self->every_param('new_ds_algorithm');
            my $digest_types = $self->every_param('new_ds_digest_type');
            my $digests      = $self->every_param('new_ds_digest');
            while ( @{$keytags} ) {
                my $keytag       = shift @{$keytags};
                my $algorithm    = shift @{$algorithms};
                my $digest_type  = shift @{$digest_types};
                my $digest       = shift @{$digests};
                next unless $keytag || $algorithm || $digest_type || $digest;

                my $extension = $frame->getNode('extension');
                if ( ! $extension ) {
                    $extension = $frame->createElement('extension');
                    $frame->getNode('command')->appendChild($extension);
                }

                my $create = $frame->getNode('secDNS:create');
                if ( ! $create ) {
                    $create = $frame->createElement('create');
                    $create->setNamespace( 'urn:ietf:params:xml:ns:secDNS-1.1', 'secDNS' );
                    $extension->appendChild($create);
                }

                my $data_element = $frame->createElement('secDNS:dsData');

                my $keytag_element = $frame->createElement('secDNS:keyTag');
                $keytag_element->appendText( $keytag );
                $data_element->appendChild($keytag_element);

                my $algorithm_element = $frame->createElement('secDNS:alg');
                $algorithm_element->appendText( $algorithm );
                $data_element->appendChild($algorithm_element);

                my $digest_type_element = $frame->createElement('secDNS:digestType');
                $digest_type_element->appendText( $digest_type );
                $data_element->appendChild($digest_type_element);

                my $digest_element = $frame->createElement('secDNS:digest');
                $digest_element->appendText( $digest );
                $data_element->appendChild($digest_element);

                $create->appendChild($data_element);
            }
            my $orderconfirmationtoken = $self->param('orderconfirmationtoken');
            if ($orderconfirmationtoken) {
                my $extension = $frame->getNode('extension');
                if ( ! $extension ) {
                    $extension = $frame->createElement('extension');
                    $frame->getNode('command')->appendChild($extension);
                }
                my $token_el = $frame->createElement('dkhm:orderconfirmationToken');
                $token_el->setNamespace('urn:dkhm:params:xml:ns:dkhm-2.0', 'dkhm');
                $token_el->appendText($orderconfirmationtoken);
                $extension->appendChild($token_el);
            }
            $self->session(
                period     => $period,
                registrant => $registrant,
            );
        }

        my $host = $self->param('host');
        if ($host) {
            if($command eq 'check') {
                $frame->addHost($host);
            } else {
                $frame->setHost($host);
            }
            $self->session(host => $host);
        }

        my $new_host = $self->param('new_host');
        if($new_host) {
            $frame->chgName($new_host);
            $self->session(new_host => $new_host);
        }

        my $userid = $self->param('userid');
        if($userid) {
            if($command eq 'check') {
                $frame->addContact($userid);
            } else {
                $frame->setContact($userid);
            }
            $self->session(userid => $userid);
        }

        my $addrs = $self->every_param('addr');
        foreach my $addr (@${addrs}) {
            if($addr) {
                my $ip = Net::IP->new($addr);
                $frame->setAddr({ 'ip' => $addr, 'version' => 'v' . ($ip ? $ip->version : '4') });
            }
        }

        my $add_addrs = $self->every_param('add_addr');
        foreach my $addr (@${add_addrs}) {
            if($addr) {
                my $ip = Net::IP->new($addr);
                $frame->addAddr({ 'ip' => $addr, 'version' => 'v' . ($ip ? $ip->version : '4') });
            } else {
                my $add_addr = $frame->getElementsByLocalName('host:add')->shift;
                $frame->getNode('host:update')->removeChild($add_addr);
            }
        }

        my $remove_addrs = $self->every_param('remove_addr');
        foreach my $addr (@${remove_addrs}) {
            if($addr) {
                my $ip = Net::IP->new($addr);
                $frame->remAddr({ 'ip' => $addr, 'version' => 'v' . ($ip ? $ip->version : '4') });
            } else {
                my $remove_addr = $frame->getElementsByLocalName('host:rem')->shift;
                $frame->getNode('host:update')->removeChild($remove_addr);
            }
        }

        my $requestedNsAdmin = $self->param('requestedNsAdmin');
        if($requestedNsAdmin) {

            my $extension = $frame->createElement('extension');

            my $nsa_element = $frame->createElement('dkhm:requestedNsAdmin');
            $nsa_element->setNamespace('urn:dkhm:params:xml:ns:dkhm-2.0', 'dkhm');
            $nsa_element->appendText($requestedNsAdmin);

            $extension->appendChild($nsa_element);
            $frame->getNode('command')->appendChild($extension);

            $self->session(requestedNsAdmin => $requestedNsAdmin);
        }

        if($object eq 'poll' and $command eq 'ack') {
            $frame->setMsgID($self->param('msgID'));
        }

        if($object eq 'contact' and $command eq 'create') {
            $frame->setContact( $self->param('contact.userid') // 'auto' );
        }

        if($object eq 'contact') {
            my $addr = {
                street => $self->every_param('contact.street'),
                city   => $self->param('contact.city'),
                pc     => $self->param('contact.zipcode'),
                cc     => $self->param('contact.country'),
            };

            if ($command eq 'create') {
                $frame->addPostalInfo('loc', $self->param('contact.name'), $self->param('contact.org'), $addr);

                my $extension = $frame->createElement('extension');

                my $user_type_element = $frame->createElement('dkhm:userType');
                $user_type_element->setNamespace('urn:dkhm:params:xml:ns:dkhm-2.0', 'dkhm');
                $user_type_element->appendText($self->param('contact.usertype'));
                $extension->appendChild($user_type_element);

                if ($self->param('contact.cvr')) {
                    my $cvr_element = $frame->createElement('dkhm:CVR');
                    $cvr_element->setNamespace('urn:dkhm:params:xml:ns:dkhm-2.0', 'dkhm');
                    $cvr_element->appendText($self->param('contact.cvr'));
                    $extension->appendChild($cvr_element);
                }

                if ($self->param('contact.pnumber')) {
                    my $pnr_element = $frame->createElement('dkhm:pnumber');
                    $pnr_element->setNamespace('urn:dkhm:params:xml:ns:dkhm-2.0', 'dkhm');
                    $pnr_element->appendText($self->param('contact.pnumber'));
                    $extension->appendChild($pnr_element);
                }

                $frame->setVoice($self->param('contact.voice')) if $self->param('contact.voice');
                $frame->setFax($self->param('contact.fax')) if $self->param('contact.fax');
                $frame->setEmail($self->param('contact.email')) if $self->param('contact.email');

                $frame->setAuthInfo;

                $frame->getNode('command')->appendChild($extension);

            } elsif ($command eq 'update') {

                if($addr->{street}[0]) {
                    $frame->chgPostalInfo('loc', $self->param('contact.name'), $self->param('contact.org'), $addr);
                } elsif ($self->param('contact.name')) {
                    $frame->chgPostalInfo('loc', $self->param('contact.name'), $self->param('contact.org'), undef);
                    my $addrnode = $frame->getNode('contact:addr');
                    $frame->getNode('contact:postalInfo')->removeChild($addrnode);
                }

                if(!$self->param('contact.name') && $addr->{street}[0]) {
                    my $namenode = $frame->getNode('contact:name');
                    $frame->getNode('contact:postalInfo')->removeChild($namenode);
                }

                my $new_password = $self->param('contact.new_password');
                if($new_password) {
                    $frame->chgAuthInfo($new_password);
                }

                #FIXME: Replace 3 if statements below with the 3 lines below
                # when and if patch sent to Net::EPP is accepted.
                #$frame->chgVoice($self->param('contact.voice')) if $self->param('contact.voice');
                #$frame->chgFax($self->param('contact.fax')) if $self->param('contact.fax');
                #$frame->chgEmail($self->param('contact.email')) if $self->param('contact.email');
                if ($self->param('contact.voice')) {
                    my $el = $frame->createElement('contact:voice');
                    $el->appendText($self->param('contact.voice'));
                    $frame->getElementsByLocalName('contact:chg')->shift->appendChild($el);
                }
                if ($self->param('contact.fax')) {
                    my $el = $frame->createElement('contact:fax');
                    $el->appendText($self->param('contact.fax'));
                    $frame->getElementsByLocalName('contact:chg')->shift->appendChild($el);
                }
                if ($self->param('contact.email')) {
                    my $el = $frame->createElement('contact:email');
                    $el->appendText($self->param('contact.email'));
                    $frame->getElementsByLocalName('contact:chg')->shift->appendChild($el);
                }

                my $addnode = $frame->getNode('contact:add');
                $frame->getNode('contact:update')->removeChild($addnode);

                my $remnode = $frame->getNode('contact:rem');
                $frame->getNode('contact:update')->removeChild($remnode);

                my $email2 = $self->param('contact.email2');
                my $mobilephone = $self->param('contact.mobilephone');
                my $cvr = $self->param('contact.cvr');
                my $pnumber = $self->param('contact.pnumber');
                my $usertype = $self->param('contact.usertype');
                my $ean = $self->param('contact.ean');
                if($email2 || $mobilephone || $cvr || $pnumber || $usertype || $ean) {
                    my $extension = $frame->createElement('extension');

                    _add_extension_element($frame, 'dkhm:pnumber', $pnumber, $extension);
                    _add_extension_element($frame, 'dkhm:CVR', $cvr, $extension);
                    _add_extension_element($frame, 'dkhm:mobilephone', $mobilephone, $extension);
                    _add_extension_element($frame, 'dkhm:secondaryEmail', $email2, $extension);
                    _add_extension_element($frame, 'dkhm:EAN', $ean, $extension);
                    _add_extension_element($frame, 'dkhm:userType', $usertype, $extension);

                    $frame->getNode('command')->appendChild($extension);
                }

            }

            my ($street1, $street2, $street3) = @{$self->every_param('contact.street')};

            $self->session(
                'contact.street'      => $street1,
                'contact.street2'     => $street2,
                'contact.street3'     => $street3,
                'contact.city'        => $self->param('contact.city'),
                'contact.zipcode'     => $self->param('contact.zipcode'),
                'contact.country'     => $self->param('contact.country'),
                'contact.name'        => $self->param('contact.name'),
                'contact.org'         => $self->param('contact.org'),
                'contact.voice'       => $self->param('contact.voice'),
                'contact.mobilephone' => $self->param('contact.mobilephone'),
                'contact.fax'         => $self->param('contact.fax'),
                'contact.email'       => $self->param('contact.email'),
                'contact.email2'      => $self->param('contact.email2'),
                'contact.usertype'    => $self->param('contact.usertype'),
                'contact.cvr'         => $self->param('contact.cvr'),
                'contact.ean'         => $self->param('contact.ean'),
                'contact.pnumber'     => $self->param('contact.pnumber'),
                'contact.userid'      => $self->param('contact.userid'),
            );
        }

        my $change_registrant = $self->param('change_registrant');
        if($change_registrant) {
            $frame->chgRegistrant( $change_registrant );
        }


        foreach my $op ( 'rem', 'add' ) {

            my $keytags      = $self->every_param($op.'_ds_keytag');
            my $algorithms   = $self->every_param($op.'_ds_algorithm');
            my $digest_types = $self->every_param($op.'_ds_digest_type');
            my $digests      = $self->every_param($op.'_ds_digest');
            while ( @$keytags ) {
                my $keytag       = shift @$keytags;
                my $algorithm    = shift @$algorithms;
                my $digest_type  = shift @$digest_types;
                my $digest       = shift @$digests;
                next unless $keytag || $algorithm || $digest_type || $digest;

                my $extension = $frame->getNode('extension');
                if ( ! $extension ) {
                    $extension = $frame->createElement('extension');
                    $frame->getNode('command')->appendChild($extension);
                }

                my $update = $frame->getNode('secDNS:update');
                if ( ! $update ) {
                    $update = $frame->createElement('update');
                    $update->setNamespace( 'urn:ietf:params:xml:ns:secDNS-1.1', 'secDNS' );
                    $extension->appendChild($update);
                }

                my $op_element = $frame->getNode("secDNS:${op}");
                if ( ! $op_element ) {
                    $op_element = $frame->createElement("secDNS:${op}");
                    $update->appendChild($op_element);
                }


                my $data_element = $frame->createElement('secDNS:dsData');

                my $keytag_element = $frame->createElement('secDNS:keyTag');
                $keytag_element->appendText( $keytag );
                $data_element->appendChild($keytag_element);

                my $algorithm_element = $frame->createElement('secDNS:alg');
                $algorithm_element->appendText( $algorithm );
                $data_element->appendChild($algorithm_element);

                my $digest_type_element = $frame->createElement('secDNS:digestType');
                $digest_type_element->appendText( $digest_type );
                $data_element->appendChild($digest_type_element);

                my $digest_element = $frame->createElement('secDNS:digest');
                $digest_element->appendText( $digest );
                $data_element->appendChild($digest_element);


                $op_element->appendChild($data_element);
            }


            my $nameserver_names     = $self->every_param($op.'_nameserver_name');
            my $nameserver_addrs     = $self->every_param($op.'_nameserver_addr');
            my @ns_data;
            while ( @$nameserver_names ) {
                my $nameserver_name     = shift @$nameserver_names;
                my $nameserver_addrs    = shift @$nameserver_addrs;
                next unless $nameserver_name;
                my @addrs = map { { addr => $_, version => (/^\d+\.\d+\.\d+\.\d+$/ ? 'v4' : 'v6') } } split /[^a-z0-9:.]+/, $nameserver_addrs;

                push @ns_data, @addrs ? { name => $nameserver_name, addrs => \@addrs } : $nameserver_name;
            }
            if ( @ns_data ) {
                ## use Data::Dumper; warn "=== NAMESERVER $op $nameserver_name $nameserver_addrs ==> ".Dumper(\@ns_data)." ===\n";
                # Use $frame->addNS() or $frame->remNS() to insert into frame.
                my $call = $op."NS";
                $frame->$call( @ns_data );
            }

            my $contact_types      = $self->every_param($op.'_contact_type');
            my $contact_userids    = $self->every_param($op.'_contact_userid');
            while ( @$contact_types ) {
                my $contact_type      = shift @$contact_types;
                my $contact_userid    = shift @$contact_userids;
                next unless $contact_type || $contact_userid;

                # Use $frame->addContact() or $frame->remContact() to insert into frame.
                my $call = $op."Contact";
                $frame->$call( $contact_type, $contact_userid );
            }


            my $status_types      = $self->every_param($op.'_status_type');
            my $status_infos      = $self->every_param($op.'_status_info');
            while ( @$status_types ) {
                my $status_type      = shift @$status_types;
                my $status_info      = shift @$status_infos;
                next unless $status_type || $status_info;

                # Use $frame->addStatus() or $frame->remStatus() to insert into frame. remStatus() does not use $status_info
                my $call = $op."Status";
                $frame->$call( $status_type, $status_info );
            }

        }

        my $oldid = $frame->getNode('clTRID');
        $frame->getNode('command')->removeChild($oldid);

        my $transactionid = $frame->createElement('clTRID');
        $transactionid->appendText( md5_hex(Time::HiRes::time().$$) );
        $frame->getNode('command')->appendChild($transactionid);

        return $frame;
    });

    $self->helper(get_logout_request => sub {
        my ($self) = @_;
        my $logout = Net::EPP::Frame::Command::Logout->new;
        $logout->clTRID->appendText( md5_hex(Time::HiRes::time().$$) );
        return $logout;
    });

    $self->helper(epp_client => sub {
        my ($self, $hostname, $port) = @_;

        my $epp = Net::EPP::Client->new(
            host       => $hostname,
            port       => $port,
            ssl        => 1,
            dom        => undef,
            frames     => 1,
        ) or die "failed to connec to epp server $hostname:$port $@";

        return $epp;

    });

    $self->helper(pretty_print => sub {
        my ($self, $epp_frame) = @_;

        my $xml_parser = XML::Twig->new( pretty_print => 'record');
        $xml_parser->parse($epp_frame->toString);

        return $xml_parser->sprint;
    });

    $self->helper(parse_reply => sub {
        my ($self, $epp_frame) = @_;

        my $reply = {
            xml            => $self->pretty_print($epp_frame),
            code           => ($epp_frame->getElementsByTagName('result'))[0]->getAttribute('code'),
            msg            => ($epp_frame->getElementsByTagName('msg'))[0]->textContent,
        };

        my $transaction_element = ($epp_frame->getElementsByTagName('svTRID'))[0];
        if($transaction_element) {
            $reply->{transaction_id} = $transaction_element->textContent;
        }

        my $reason_element = ($epp_frame->getElementsByTagName('domain:reason'))[0];
        if($reason_element) {
            $reply->{reason} = $reason_element->textContent;
        }

        my $host_reason_element = ($epp_frame->getElementsByTagName('host:reason'))[0];
        if($host_reason_element) {
            $reply->{reason} = $host_reason_element->textContent;
        }

        my $contact_reason_element = ($epp_frame->getElementsByTagName('contact:reason'))[0];
        if($contact_reason_element) {
            $reply->{reason} = $contact_reason_element->textContent;
        }

        my $domainname_element = ($epp_frame->getElementsByTagName('domain:name'))[0];
        if($domainname_element) {
            $reply->{domain} = $domainname_element->textContent;
            if (defined $domainname_element->getAttribute('avail')) {
                $reply->{avail} = $domainname_element->getAttribute('avail');
            }
        }

        my $hostname_element = ($epp_frame->getElementsByTagName('host:name'))[0];
        if($hostname_element) {
            $reply->{host} = $hostname_element->textContent;
            if (defined $hostname_element->getAttribute('avail')) {
                $reply->{avail} = $hostname_element->getAttribute('avail');
            }
        }

        my $contactid_element = ($epp_frame->getElementsByTagName('contact:id'))[0];
        if($contactid_element) {
            $reply->{id} = $contactid_element->textContent;
            if (defined $contactid_element->getAttribute('avail')) {
                $reply->{avail} = $contactid_element->getAttribute('avail');
            }
        }

        my $host_element = ($epp_frame->getElementsByTagName('host:infData'));
        if($host_element) {
            my $info = ( $reply->{host_data} //= {} );

            _text_element_into( $epp_frame, 'host:name',   $info, 'name'   );
            _text_element_into( $epp_frame, 'host:roid',   $info, 'roid' );

            my $status = "status";
            foreach my $ele ( _elements( $epp_frame, 'host:status' ) ) {
                my $s = $ele->{"s"};
                $info->{ $status } = $s;
                $status .= " ";  # A new key, but space is not visible
            }

            my $addr = "addr";
            foreach my $ele ( _elements( $epp_frame, 'host:addr' ) ) {
                $info->{ $addr } = $ele->textContent . " (". $ele->{"ip"} . ")";
                $addr .= " ";  # A new key, but space is not visible
            }

            _text_element_into( $epp_frame, 'host:clID',     $info, 'clID' );
            _text_element_into( $epp_frame, 'host:crID',     $info, 'crID' );
            _text_element_into( $epp_frame, 'host:crDate',   $info, 'crDate' );

        }

        my($domain_element) = _elements( $epp_frame, 'domain:infData');
        if($domain_element) {
            my $info = ( $reply->{domain_data} //= {} );

            _text_element_into( $epp_frame, 'domain:name',   $info, 'name'   );
            _text_element_into( $epp_frame, 'domain:roid',   $info, 'roid' );

            #  <domain:status s="serverDeleteProhibited"/>
            my $status = "status";
            foreach my $ele ( _elements( $epp_frame, 'domain:status' ) ) {
                my $s = $ele->{"s"};
                $info->{ $status } = $s;
                $status .= " "; # A new key, but space is not visible
            }

            _text_element_into( $epp_frame, 'domain:registrant', $info, 'registrant' );

            foreach my $ele ( _elements( $epp_frame, 'domain:contact' ) ) {
                my $type = $ele->getAttribute("type");
                my $userid = $ele->textContent;
                $info->{ $type } = $userid;
            }

            _text_element_into( $epp_frame, 'domain:hostObj',    $info, 'ns' );
            _text_element_into( $epp_frame, 'domain:host',       $info, 'host' );
            _text_element_into( $epp_frame, 'domain:clID',       $info, 'clID' );
            _text_element_into( $epp_frame, 'domain:crID',       $info, 'crID' );
            _text_element_into( $epp_frame, 'domain:crDate',     $info, 'crDate' );
            _text_element_into( $epp_frame, 'domain:exDate',     $info, 'exDate' );

        }

        my($contact_element) = _elements( $epp_frame, 'contact:infData');
        if($contact_element) {
            my $info = ( $reply->{contact_data} //= {} );

            _text_element_into( $epp_frame, 'contact:id',     $info, 'id'   );
            _text_element_into( $epp_frame, 'contact:roid',   $info, 'roid' );
            _text_element_into( $epp_frame, 'contact:org',    $info, 'org'  );
            _text_element_into( $epp_frame, 'contact:name',   $info, 'name' );
            _text_element_into( $epp_frame, 'contact:street', $info, 'street' );
            _text_element_into( $epp_frame, 'contact:city',   $info, 'city' );
            _text_element_into( $epp_frame, 'contact:pc',     $info, 'pc' );
            _text_element_into( $epp_frame, 'contact:cc',     $info, 'cc' );
            _text_element_into( $epp_frame, 'contact:voice',  $info, 'voice' );
            _text_element_into( $epp_frame, 'contact:fax',    $info, 'fax' );
            _text_element_into( $epp_frame, 'contact:email',  $info, 'email' );
            _text_element_into( $epp_frame, 'contact:clID',   $info, 'clID' );
            _text_element_into( $epp_frame, 'contact:crID',   $info, 'crID' );
            _text_element_into( $epp_frame, 'contact:crDate', $info, 'crDate' );

            #  <contact:status s="serverDeleteProhibited"/>
            my $status = "status";
            foreach my $ele ( _elements( $epp_frame, 'contact:status' ) ) {
                my $s = $ele->{"s"};
                $info->{ $status } = $s;
                $status .= " ";
            }
        }

        my $contact_created_element = ($epp_frame->getElementsByTagName('contact:creData'))[0];
        if($contact_created_element) {
            my $info = ( $reply->{contact_data} //= {} );
            _text_element_into( $epp_frame, 'contact:id',     $info, 'id' );
            _text_element_into( $epp_frame, 'contact:crDate', $info, 'crDate' );
        }

        my $domain_created_element = ($epp_frame->getElementsByTagName('domain:creData'))[0];
        if($domain_created_element) {
            my $info = ( $reply->{domain_data} //= {} );
            _text_element_into( $epp_frame, 'domain:name',   $info, 'name' );
            _text_element_into( $epp_frame, 'domain:crDate', $info, 'crDate' );
            _text_element_into( $epp_frame, 'domain:exDate', $info, 'exDate' );
        }

        my $host_created_element = ($epp_frame->getElementsByTagName('host:creData'))[0];
        if($host_created_element) {
            my $info = ( $reply->{host_data} //= {} );
            _text_element_into( $epp_frame, 'host:name',   $info, 'name' );
            _text_element_into( $epp_frame, 'host:crDate', $info, 'crDate' );
        }

        my $msgq_element = ($epp_frame->getElementsByTagName('msgQ'))[0];
        if($msgq_element) {
            my $info = ( $reply->{msgQ} //= {} );
            $info->{count} = $msgq_element->getAttribute("count");
            $info->{id}    = $msgq_element->getAttribute("id");
            my $message_element = ($msgq_element->getElementsByTagName('msg'))[0];
            if($message_element) {
                $info->{msg} = $message_element->textContent;
            }
        }

        my $extension_element = ($epp_frame->getElementsByTagName('extension'))[0];
        if($extension_element) {
            my $info = ( $reply->{extension} //= {} );
            _text_element_into( $epp_frame, 'dkhm:mobilephone', $info, 'dkhm:mobilephone' );
            _text_element_into( $epp_frame, 'dkhm:secondaryEmail', $info, 'dkhm:secondaryEmail' );
            _text_element_into( $epp_frame, 'dkhm:contact_validated', $info, 'dkhm:contact_validated' );
            _text_element_into( $epp_frame, 'dkhm:domain_confirmed', $info, 'dkhm:domain_confirmed' );
            _text_element_into( $epp_frame, 'dkhm:registrant_validated', $info, 'dkhm:registrant_validated' );
            _text_element_into( $epp_frame, 'dkhm:risk_assessment', $info, 'dkhm:risk_assessment' );

            foreach my $ele ( _elements( $epp_frame, 'dkhm:domainAdvisory' ) ) {
                my $advisory = $ele->getAttribute("advisory");
                my $domain   = $ele->getAttribute("domain");
                my $date     = $ele->getAttribute("date");
                $info->{ "Advisory: $advisory" } = join ' / ', $domain, $date//();
            }
        }

        return $reply;
    });

    $self->helper(commands_from_object => sub {
        my ($self, $object) = @_;

        my @values;

        if ($object eq 'host') {
            @values = ['check', 'create', 'delete', 'info', 'update'];
        } elsif ($object eq 'domain') {
            @values = ['check', 'create', 'info', 'renew', 'update'];
        } elsif ($object eq 'contact') {
            @values = ['check', 'create', 'info', 'update'];
        } elsif ($object eq 'poll') {
            @values = ['req', 'ack' ];
        }

        return @values;
    });

    # Normal route to controller
    $r->get('/')->to('client#index');
    $r->get('/login')->to('client#index');
    $r->get('/logout')->to('client#logout');
    $r->post('/login')->to('client#login');
    $r->post('/execute')->to('client#execute');
    $r->get('/execute' => sub{ shift->redirect_to('/') });

    # Ajax requests
    $r->post('/get_login_xml')->to('ajax#get_login_xml');
    $r->post('/get_request_xml')->to('ajax#get_request_xml');
    $r->post('/get_commands_from_object')->to('ajax#get_commands_from_object');
    $r->post('/get_command_form')->to('ajax#get_command_form');

}

sub _elements {
    my($xml, $tag_name) = @_;
    if ( ! $xml ) { return; }
    my @elements = map { ref($_) eq "ARRAY" ? ( @$_ ) : $_ } $xml->getElementsByTagName($tag_name);
    return @elements;
}

sub _text_elements {
    my($xml, $tag_name) = @_;
    my @elements = _elements( $xml, $tag_name );
    my(@texts) = map { UNIVERSAL::can($_, 'textContent')  ? $_->textContent : $_ } @elements;
}

sub _text_element_into {
    my($xml, $tag_name, $dest_hash, $dest_name ) = @_;
    my(@texts) = _text_elements( $xml, $tag_name );
    if ( ! @texts ) { return; }

    my $number = "";

    foreach my $text ( @texts ) {

        $dest_hash->{$dest_name.$number} = $text;

        $number ||= 1;
        $number++;
    }
}

sub _add_extension_element {
    my($xml_frame, $element_name, $value, $extension_element) = @_;

    if($value) {
        my $element = $xml_frame->createElement($element_name);
        $element->setNamespace('urn:dkhm:params:xml:ns:dkhm-2.0', 'dkhm');
        $element->appendText($value);
        $extension_element->appendChild($element);
    }
}

# Central storage of connections to the EPP server. The connection id
# is stored in session and EPP connections will live between browser
# requests.
my %connections;

sub add_connection {
    my ($self, $id, $connection) = @_;
    $connections{$id} = $connection;
}

sub get_connection {
    my ($self, $id) = @_;
    return $connections{$id};
}

sub expire_connection {
    my ($self, $id) = @_;
    if($connections{$id}) {
        try {
            $connections{$id}->disconnect;
        } catch($err) {

        }
        delete $connections{$id};
    }
}


1;
