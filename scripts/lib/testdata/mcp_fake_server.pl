#!/usr/bin/env perl
# A stdio MCP server for scripts/lib/test_mcp_lazy.sh. It logs to $FAKE_LOG
# ("start PID", "recv METHOD", "eof") and answers:
#   initialize   (an error with FAKE_INIT_FAIL=1)
#   tools/list   the tools named in FAKE_TOOLS (default "a,b")
#   tools/call   echo: its arguments back; big: a 5 MiB text; bigrpc: a
#                2 MiB one, jsonrpc first and the id last; crash: exit 3
# FAKE_INSTR=TEXT adds instructions to its initialize answer.
# FAKE_CHILD=FILE starts a `sleep 300` beside it and writes its pid there;
# FAKE_STUBBORN=1 ignores TERM and stdin's end. Answers put the id last, as
# the TypeScript SDK does, except echo's, which puts it first.
use strict;
use warnings;
use JSON::PP ();

my $J = JSON::PP->new->utf8->canonical;
$| = 1;
sub logf {
    return unless $ENV{FAKE_LOG};
    open my $fh, '>>', $ENV{FAKE_LOG} or return;
    print {$fh} "@_\n";
}
sub answer { my ($id, $r) = @_; print '{"result":', $J->encode($r), ',"jsonrpc":"2.0","id":', $J->encode($id), "}\n" }

logf("start $$");
if ($ENV{FAKE_CHILD}) {
    my $c = fork;
    if (defined $c && $c == 0) { exec 'sleep', '300' }
    open my $fh, '>', $ENV{FAKE_CHILD}; print {$fh} "$c\n"; close $fh;
}
$SIG{TERM} = 'IGNORE' if $ENV{FAKE_STUBBORN};

while (my $line = <STDIN>) {
    my $m = eval { $J->decode($line) } or next;
    my $method = $m->{method} // 'answer';
    logf("recv $method");
    next unless exists $m->{id} && defined $m->{method};
    my $id = $m->{id};
    if ($method eq 'initialize') {
        if ($ENV{FAKE_INIT_FAIL}) {
            print $J->encode({ jsonrpc => '2.0', id => $id, error => { code => -32000, message => 'nope' } }), "\n";
            next;
        }
        answer($id, { protocolVersion => $m->{params}{protocolVersion}, capabilities => { tools => {} },
                      serverInfo => { name => 'fake', version => '1' },
                      ($ENV{FAKE_INSTR} ? (instructions => $ENV{FAKE_INSTR}) : ()) });
    } elsif ($method eq 'tools/list') {
        answer($id, { tools => [ map { { name => $_, inputSchema => { type => 'object' } } } split /,/, ($ENV{FAKE_TOOLS} // 'a,b') ] });
    } elsif ($method eq 'tools/call') {
        my $tool = $m->{params}{name} // '';
        exit 3 if $tool eq 'crash';
        if ($tool eq 'bigrpc') {
            print '{"jsonrpc":"2.0","result":', $J->encode({ content => [ { type => 'text', text => 'y' x (2 << 20) } ] }),
                  ',"id":', $J->encode($id), "}\n";
        } elsif ($tool eq 'echo') {
            print '{"id":', $J->encode($id), ',"jsonrpc":"2.0","result":',
                  $J->encode({ content => [ { type => 'text', text => $J->encode($m->{params}{arguments} // {}) } ] }), "}\n";
        } else {
            answer($id, { content => [ { type => 'text', text => ($tool eq 'big' ? 'x' x (5 << 20) : $tool) } ] });
        }
    } else {
        print $J->encode({ jsonrpc => '2.0', id => $id, error => { code => -32601, message => 'no such method' } }), "\n";
    }
}
logf('eof');
sleep 300 if $ENV{FAKE_STUBBORN};
