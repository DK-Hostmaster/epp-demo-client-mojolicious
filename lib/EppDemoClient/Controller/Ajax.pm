package EppDemoClient::Controller::Ajax;
use Mojo::Base 'Mojolicious::Controller';

use TryCatch;
use Mojo::Util qw(xml_escape);
use Digest::MD5 qw(md5_hex);
use Time::HiRes;

sub get_login_xml {
    my $self = shift;

    my $username = $self->param('username');
    my $password = $self->param('password');

    my $login_command = $self->get_login_request($username, $password);

    $self->render(text => xml_escape($self->pretty_print($login_command)));
}

sub get_request_xml {
    my $self = shift;

    my $request_frame = $self->get_request_frame;

    $self->render(text => xml_escape($self->pretty_print($request_frame)));
}

sub get_commands_from_object {
    my $self = shift;
    my $object = $self->param('object');

    $self->app->log->info("Get commands from object $object");

    $self->stash(name => 'command');
    $self->session(values => $self->commands_from_object($object));

    $self->render(template => 'includes/select');
}

sub get_command_form {
    my $self = shift;
    my $object  = $self->param('object');
    my $command = $self->param('command');

    $self->app->log->info("Get command form for object $object and command $command");

    $self->render(template => "commands/$object/$command");
}

1;
