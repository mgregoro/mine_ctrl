#
# (c) 2014 lolz
#

package MineCtrl::Controller::Server;

use Mojo::Base 'Mojolicious::Controller';

# we would want to put ACL stuff in here prolly yea
sub default {
    my ($self) = @_;

    # increase the connection timeout
    Mojo::IOLoop->stream($self->tx->connection)->timeout(3600); # 1 hr.

    # every client gets ALL the scroll (might want to trim it to the last 20 lines but whatever)
    foreach my $line (@{$self->line_cache}) {
        $self->send({ text => $line });
    }

    # send input to the java process
    $self->on(message => sub {
        my ($ws, $msg) = @_;

        # prettier echo feedback (now to everyone)
        while (my ($id, $ws) = each %{$self->active_ws}) {
            $ws->send({ text => " ::> $msg<br\>" });
        }

        push(@{$self->line_cache}, " ::> $msg<br\>");

        if ($msg eq "/restart") {
            my $restart_line = scalar(localtime) . ": restarting server.<br\>";
            push(@{$self->line_cache}, $restart_line);

            while (my ($id, $ws) = each %{$self->active_ws}) {
                $ws->send({ text => $restart_line });
                $ws->finish;
            }

            $self->restart_server;
        } else {
            # this is a command from the browser, just write it to the java process.
            my $jin = $self->jin;
            print $jin "$msg\n";
        }
    });

    # this is data from the java process.
    my $jout = $self->jout;
    my $ws_id = `head -5 /dev/urandom | base64 | tr -d '+/=' | cut -c 1-32 | head -1`;
    chomp($ws_id);

    # clean shutdown.
    $self->on(finish => sub {
        # don't clean
        delete $self->active_ws->{$ws_id};
    });
    
    # hmm..
    $self->active_ws->{$ws_id} = $self;
}

1;
