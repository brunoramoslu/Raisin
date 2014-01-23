
use strict;
use warnings;

use FindBin '$Bin';
use HTTP::Request::Common;
use Plack::Test;
use Plack::Util;
use Test::More;
use YAML 'Load';

use lib "$Bin/../lib";

my $app = Plack::Util::load_psgi("$Bin/../eg/lite/simple.pl");
my $t;

my %NEW_USER = (
    name     => 'Obi-Wan Kenobi',
    password => 'somepassword',
    email    => 'ow.kenobi@jedi.com',
);
my @USER_IDS;

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(GET '/user');

    subtest 'GET /user' => sub {
        if (!is $res->code, 200) {
            diag $res->content;
            BAIL_OUT 'FAILED!';
        }
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        @USER_IDS = map { $_->{id} } grep { $_ } @{ $o->{data} };
        ok scalar @USER_IDS, 'data';
    };
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(POST '/user', [%NEW_USER]);

    subtest 'POST /user' => sub {
        if (!is $res->code, 200) {
            diag $res->content;
            BAIL_OUT 'FAILED!';
        }
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        is $o->{success}, $USER_IDS[-1] + 1, 'success';
        push @USER_IDS, $o->{success};
    };
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(GET "/user/$USER_IDS[-1]");

    subtest "GET /user/$USER_IDS[-1]" => sub {
        if (!is $res->code, 200) {
            diag $res->content;
            BAIL_OUT 'FAILED!';
        }
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        is_deeply $o->{data}, \%NEW_USER, 'data';
    };
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(PUT "/user/$USER_IDS[-1]", [password => 'newpassword']);

    subtest "PUT /user/$USER_IDS[-1]" => sub {
        if (!is $res->code, 200) {
            diag $res->content;
            BAIL_OUT 'FAILED!';
        }
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        is $o->{success}, 1, 'success';
    };
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(PUT "/user/$USER_IDS[-1]/bump");

    subtest "PUT /user/$USER_IDS[-1]/bump" => sub {
        if (!is $res->code, 200) {
            diag $res->content;
            BAIL_OUT 'FAILED!';
        }
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        ok $o->{success}, 'success';
    };
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(GET "/user/$USER_IDS[-1]/bump");

    subtest "GET /user/$USER_IDS[-1]/bump" => sub {
        if (!is $res->code, 200) {
            diag $res->content;
            BAIL_OUT 'FAILED!';
        }
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        ok $o->{data}, 'data';
    };
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->(GET "/failed");

    subtest "GET /failed" => sub {
        is $res->code, 409;
        ok my $c = $res->content, 'content';
        ok my $o = Load($c), 'decode';
        is $o->{data}, 'BROKEN!', 'data';
    };
};

done_testing;
exit;

#$t = Plack::Test->create($app);
#my $res = $t->request(GET "/user/2?view=all&view=none");
#diag $res->content;
#
#note ' *** ' x 5;
#
#$t = Plack::Test->create($app);
#$res = $t->request(PUT "/user/2/bump");
#diag $res->content;
#
#$t = Plack::Test->create($app);
#$res = $t->request(PUT "/user/2/bump");
#diag $res->content;
#
#note ' *** ' x 5;
#
#$t = Plack::Test->create($app);
#$res = $t->request(GET "/user/2/bump");
#diag $res->content;
#
#note ' *** ' x 5;
#
#$t = Plack::Test->create($app);
#$res = $t->request(GET "/user/2");
#diag $res->content;
#
#note ' *** ' x 5;
#
#$t = Plack::Test->create($app);
#$res = $t->request(GET "/failed");
#diag $res->content;
