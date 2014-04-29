#
# (c) 2014 lolz
#

package MineCtrl::Controller::Home;

use Mojo::Base 'Mojolicious::Controller';

# we would want to put ACL stuff in here prolly yea
sub default {
    my ($self) = @_;

    $self->render(template => 'home/default');
}

1;
