package MineCtrl;
use Mojo::Base 'Mojolicious';
use IPC::Open2;
use Mojo::IOLoop;
use IO::Handle;

use utf8;

my ($pid, $jin, $jout, $config);

# This method will run once at server start
sub startup {
    my ($self) = @_;

    $config = $self->plugin('Mojolicious::Plugin::Config', { file => 'etc/mine_ctrl.conf' });

    chdir($config->{server_root});
    my $command = "$config->{command} 2>&1";

    $pid = open2($jout, $jin, $command);
    $jout->autoflush;
    $jin->autoflush;

    # so, now we should have a reader and writer for the jvm process running the server
    # we need a websocket handler and a regular HTTP handler to load the "page"

    # used to store previous lines for first connect...
    my @line_cache;

    # websockets to service
    my %active_ws;

    # Helpers to access our IO handles
    $self->helper(jin => sub {
        return $jin;
    });

    $self->helper(jout => sub {
        return $jout;
    });

    # keep track of line cache and active websockets
    $self->helper(line_cache => sub {
        return \@line_cache;
    });

    $self->helper(active_ws => sub {
        return \%active_ws;
    });

    $self->helper(reactor_hook => sub {
        my ($self, $jout) = @_;

        Mojo::IOLoop->singleton->reactor->io(
            $jout => sub {
                my ($reactor) = @_;

                my ($output, $lines);

                # this will get it all.
                while(1) {
                    sysread($jout, $output, 4096, 0);
                    $lines .= $output;
                    last if length($output) < 4096;
                }

                $lines =~ s/\n/<br\/>/g;

                if (length($lines) == 0) {
                    Mojo::IOLoop->singleton->reactor->remove($jout);
                    while (my ($id, $ws) = each %{$self->active_ws}) {
                        $ws->send({ text => scalar(localtime) . " SERVER DEAD, RESTARTING.<br/>" });
                        $ws->finish;
                    }
                    $self->restart_server;
                } else {
                    # might need to shift this to unshift, my brain isn't working.
                    push(@{$self->line_cache}, $lines);

                    while (my ($id, $ws) = each %{$self->active_ws}) {
                        if ($ENV{MINECTRL_DEBUG}) {
                            warn "Writing " . length($lines) . " bytes to connection ID $id\n";
                        }
                        $ws->send({ text => $lines });
                    }
                }
            }
        )->watch($jout, 1, 0);
    });

    $self->helper(restart_server => sub {
        # clean up the old filehandles and java process
        close($jin);
        close($jout);
        kill("INT", $pid);
        waitpid($pid, 0);

        # re-start the java process. (open2 and open3 behave like PHP functions..  fucking backwards ordering)
        open2($jout, $jin, $command);

        $jout->autoflush;
        $jin->autoflush;

        # empty the line cache and active websockets, we're starting over.
        @line_cache = ();
        %active_ws = ();
        $self->reactor_hook($jout)
    });

    # Router
    my $r = $self->routes;

    $r->route('/')->to('controller-home#default');
    $r->websocket('/srvr')->to('controller-server#default');

    # hook in the reactor to our started process.
    $self->reactor_hook($jout);
}

sub DESTROY {
    my ($self) = @_;
    close($jin);
    close($jout);
    kill("INT", $pid);
    waitpid($pid, 0);
}

1;

