package EppDemoClient::Controller::Client;
use Mojo::Base 'Mojolicious::Controller';

use Benchmark;

use TryCatch;

use Net::EPP::Frame::Hello;

use Mojo::Util qw(xml_escape);
use Digest::MD5 qw(md5_hex);
use Time::HiRes;

# The frontpage.
sub index {
    my $self = shift;

    my $connection_id = $self->session('connection_id');
    if($connection_id) {
        $self->app->log->info("Found connection_id in session: $connection_id");
        my $epp = $self->app->get_connection($connection_id);
        if ($epp) {
            $self->app->log->info("Found EPP connection in session $epp");

            try {
                my $hello = Net::EPP::Frame::Hello->new;

                $self->app->log->info("Sending hello command [" . $hello->toString . "]");
                my $answer = $epp->request($hello);
                $self->app->log->info("Reply to hello command [" . $answer->toString . "]");
                my $hello_reply = $self->parse_reply($answer);
                $self->stash(logged_in => 1);
                $self->stash(hello_reply => $answer->toString);
            } catch ($err) {
                $self->app->log->error("Keep alive call failed: $err");
                $self->app->expire_connection($connection_id);
                delete $self->session->{connection_id};
            }
        } else {
            delete $self->session->{connection_id};
        }
    }

    $self->stash(available_hosts => $self->config->{available_hosts});

    $self->render();
}

sub logout {
    my $self = shift;
    my $connection_id = $self->session('connection_id');
    if($connection_id) {
        my $epp = $self->app->get_connection($connection_id);
        if ($epp) {
            $self->app->log->info("Found EPP connection in session $epp");

            try {
                my $logout = $self->get_logout_request;
                $self->app->log->info("Sending logout command [" . $logout->toString . "]");
                my $start = Benchmark->new;
                my $answer = $epp->request($logout);
                $self->app->log->info("Reply to logout command [" . $answer->toString . "]");
                my $end = Benchmark->new;
                my $timediff = timediff($end, $start);
                $self->stash(execute_time => timestr($timediff, 'nop'));

                $self->stash(command_reply => $self->parse_reply($answer));

            } catch ($err) {
                # Croak traceback may appear at end of $err - We do not need that in output.
                $self->app->log->warn( sprintf('Failed to send logout command: %s', $err =~ s/\n.*\z//s) );
            }
        }
        $self->app->expire_connection($connection_id);
    }
    delete $self->session->{connection_id};
    $self->stash(message => 'Logged out');

    $self->stash(available_hosts => $self->config->{available_hosts});

    $self->render(template => 'client/index');
}

sub login {
    my $self = shift;

    my $hostname = $self->param('hostname');
    my $port     = $self->param('port');
    my $username = $self->param('username');
    my $password = $self->param('password');

    my $start = Benchmark->new;

    my $login_reply = $self->_perform_login($hostname, $port, $username, $password);

    my $end = Benchmark->new;
    my $timediff = timediff($end, $start);
    $self->stash(execute_time => timestr($timediff, 'nop'));

    $self->session(
        username => $username,
        password => $password,
        hostname => $hostname,
        port     => $port
    );

    $self->stash(command_reply => $login_reply);

    $self->stash(available_hosts => $self->config->{available_hosts});

    $self->render(template => 'client/index');
}

sub _perform_login {
    my ($self, $hostname, $port, $username, $password) = @_;

    my $login_command = $self->get_login_request($username, $password);

    $self->app->log->info("Connecting to $hostname:$port");

    my $epp;
    try {
    # Notice. This may fail if connection cannot be established. This returns invalid XML. TODO: FIX.
        $epp = $self->epp_client($hostname, $port);
    } catch ($err) {
        $self->app->log->error(sprintf('Connection to epp_client host %s port %s failed: %s', $hostname, $port, $err));
        return { code => 2500 };
    }

    my $greeting = $epp->connect(
        SSL_version         => 'TLSv12',
        SSL_verify_mode     => 0,    # 0 = disable SSL verify,  3 = 1+2
        SSL_use_cert        => 1,
        SSL_verifycn_name   => $hostname,
    );

    $self->app->log->info("Sending login command [" . $login_command->toString . "]");

    my $answer = $epp->request($login_command);

    $self->app->log->info("Reply to login command [" . $answer->toString . "]");

    my $login_reply = $self->parse_reply($answer);

    if($login_reply->{code} == 1000) {
        $self->app->log->info("Login was successful, store username and password in session");
        $self->stash(logged_in => 1);
        $self->app->add_connection($login_reply->{transaction_id}, $epp);
        $self->session(connection_id => $login_reply->{transaction_id});
        $self->app->log->info("Logged in, save connection_id " . $login_reply->{transaction_id});
    }

    if($login_reply->{code} == 1000) {
        my $hello = Net::EPP::Frame::Hello->new;
        $self->app->log->info("Sending hello command [" . $hello->toString . "]");
        my $answer = $epp->request($hello);
        $self->app->log->info("Reply to hello command [" . $answer->toString . "]");
        my $hello_reply = $self->parse_reply($answer);
        $self->stash(hello_reply => $answer->toString);
    }

    return $login_reply;
}

sub execute {
    my $self = shift;

    my $object  = $self->param('object');
    my $command = $self->param('command');

    my $connection_id = $self->session('connection_id');

    # Try to reconnect if session has credentials
    my $hostname = $self->session->{hostname};
    my $port     = $self->session->{port};
    my $username = $self->session->{username};
    my $password = $self->session->{password};
    my $login_ok = 0;

    if($connection_id) {
        my $epp = $self->app->get_connection($connection_id);

        # If we have a connection, test it and fail it if broken.
        if ($epp) {
            try {
                my $hello = Net::EPP::Frame::Hello->new;
                $self->app->log->info("Sending hello command [" . $hello->toString . "]");
                my $answer = $epp->request($hello);
                $self->app->log->info("Reply to hello command [" . $answer->toString . "]");
                my $hello_reply = $self->parse_reply($answer);
                $self->stash(logged_in => 1);
                $self->stash(hello_reply => $answer->toString);
                $login_ok = 1;
            } catch ($err) {
                $self->app->log->error("Keep alive call failed: $err");
                $self->app->expire_connection($connection_id);
                delete $self->session->{connection_id};
            }
        }

        # Unless we have a working connection, try to login.
        if(!$login_ok) {
            $self->app->log->info("Try to login again at $hostname:$port with $username");
            if ($hostname && $username) {
                my $login_reply = $self->_perform_login($hostname, $port, $username, $password);
                if($login_reply->{code} == 1000) {
                    $connection_id = $login_reply->{transaction_id};
                    $epp = $self->app->get_connection($connection_id);
                    $login_ok = 1;
                }
            }

            unless($login_ok) {
                $self->stash(available_hosts => $self->config->{available_hosts});

                $self->render(template => 'client/index');
                return;
            }
        }

        my $frame = $self->get_request_frame;

        my $start = Benchmark->new;
        $self->app->log->info("Sending command [" . $frame->toString . "]");
        my $answer = $epp->request($frame);
        $self->app->log->info("Reply to command [" . $answer->toString . "]");
        my $end = Benchmark->new;
        my $timediff = timediff($end, $start);
        $self->stash(execute_time => timestr($timediff, 'nop'));

        my $command_reply = $self->parse_reply($answer);
        $self->stash(command_reply => $command_reply);

        # command failed, server closing connection
        if($command_reply->{code} == 2500) {
            $self->app->expire_connection($connection_id);
            delete $self->session->{connection_id};
            $self->stash(logged_in => 0);
        }

    } else {
        $self->app->log->info("Found no connection_id in session");
    }

    $self->session(object => $object);
    $self->session(command => $command);
    $self->session(values => $self->commands_from_object($object));

    $self->stash(available_hosts => $self->config->{available_hosts});

    $self->render(template => 'client/index');
}

1;
