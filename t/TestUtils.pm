#!/usr/bin/env perl

package TestUtils;

#########################
# Test Utils
#########################
BEGIN {
  $ENV{'THRUK_SRC'} = 'TEST';

  $ENV{'CATALYST_SERVER'} =~ s#/$##gmx if $ENV{'CATALYST_SERVER'};
}

###################################################
use lib 'lib';
use strict;
use Data::Dumper;
use Test::More;
use URI::Escape;
use Encode qw/decode_utf8/;
use File::Slurp;
use HTTP::Request::Common qw(POST);
use HTTP::Response;
use HTTP::Cookies::Netscape;
use LWP::UserAgent;
use File::Temp qw/ tempfile /;
use HTML::Entities qw//;
use Carp;
use Thruk::Utils;
use Thruk::Utils::External;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT    = qw(request ctx_request);
our @EXPORT_OK = qw(request ctx_request);

use Test::Mojo;
my $mojo = Test::Mojo->new('Thruk');

my $use_html_lint = 0;
my $lint;
eval {
    require HTML::Lint;
    $use_html_lint = 1;
    $lint          = new HTML::Lint;
};

#########################
sub request {
    my($url) = @_;
    my $tx;
    my $req;
    if(ref $url eq "") {
        $tx = $mojo->ua->build_tx(GET => $url);
        $req = HTTP::Request->new(GET => $url);
    } else {
        $req    = $url;
        my $url = "".$req->uri();
        $url    =~ s|^\Qhttp://localhost.local\E||gmx;
# TODO: add post data
        $tx     = $mojo->ua->build_tx($req->method => $url);
    }
    $mojo->tx($mojo->ua->start($tx));
    my $res = HTTP::Response->parse($tx->res->to_string);
    $res->request($req);
    return($res);
}

#########################
sub ctx_request {
    my($url) = @_;
    require Mojo::Server;
    require HTTP::Response;
    my $tx   = $mojo->ua->build_tx(GET => $url);
    $mojo->tx($mojo->ua->start($tx));
    my $res  = HTTP::Response->parse($tx->res->to_string);
    $res->request(HTTP::Request->new(GET => $url));
    my $c    = $Thruk::Request::c;
    $c->tx($tx);
    return($res, $c);
}

#########################
sub get_test_servicegroup {
    my $request = _request('/thruk/cgi-bin/status.cgi?servicegroup=all&style=overview');
    ok( $request->is_success, 'get_test_servicegroup() needs a proper config page' ) or diag(Dumper($request));
    my $page = $request->content;
    my $group;
    if($page =~ m/extinfo\.cgi\?type=8&amp;servicegroup=(.*?)'>(.*?)<\/a>/mxo) {
        $group = $1;
    }
    isnt($group, undef, "got a servicegroup from config.cgi") or bail_out_req('got no test servicegroup, cannot test.', $request);
    return($group);
}

#########################
sub get_test_hostgroup {
    my $request = _request('/thruk/cgi-bin/status.cgi?hostgroup=all&style=overview');
    ok( $request->is_success, 'get_test_hostgroup() needs a proper config page' ) or diag(Dumper($request));
    my $page = $request->content;
    my $group;
    if($page =~ m/'extinfo\.cgi\?type=5&amp;hostgroup=(.*?)'>(.*?)<\/a>/mxo) {
        $group = $1;
    }
    isnt($group, undef, "got a hostgroup from config.cgi") or bail_out_req('got no test hostgroup, cannot test.', $request);
    return($group);
}

#########################
sub get_test_user {
    our $remote_user_cache;
    return $remote_user_cache if $remote_user_cache;
    my $request = _request('/thruk/cgi-bin/status.cgi?hostgroup=all&style=hostdetail');
    ok( $request->is_success, 'get_test_user() needs a proper config page' ) or diag(Dumper($request));
    my $page = $request->content;
    my $user;
    if($page =~ m/Logged\ in\ as\ <i>(.*?)<\/i>/mxo) {
        $user = $1;
    }
    isnt($user, undef, "got a user from config.cgi") or bail_out_req('got no test user, cannot test.', $request);
    $remote_user_cache = $user;
    return($user);
}

#########################
sub get_test_service {
    my $backend = shift;
    my $request = _request('/thruk/cgi-bin/status.cgi?style=hostdetail&dfl_s0_type=number+of+services&dfl_s0_val_pre=&dfl_s0_op=>%3D&dfl_s0_value=1'.(defined $backend ? '&backend='.$backend : ''));
    ok( $request->is_success, 'get_test_service() needs a proper status page' ) or diag(Dumper($request));
    my $page = $request->content;
    my($host,$service);
    if($page =~ m/extinfo\.cgi\?type=1&amp;host=(.*?)&amp;backend/mxo) {
        $host = $1;
    }
    isnt($host, undef, "got a host from status.cgi") or bail_out_req('got no test host, cannot test.', $request);

    $request = _request('/thruk/cgi-bin/status.cgi?host='.$host.(defined $backend ? '&backend='.$backend : ''));
    $page = $request->content;
    if($page =~ m/extinfo\.cgi\?type=2&amp;host=(.*?)&amp;service=(.*?)&/mxo) {
        $host    = $1;
        $service = $2;
    }
    isnt($service, undef, "got a service from status.cgi") or bail_out_req('got no test service, cannot test.', $request);
    $service = uri_unescape($service);
    $host    = uri_unescape($host);

    return($host, $service);
}

#########################
sub get_test_timeperiod {
    my $request = _request('/thruk/cgi-bin/config.cgi?type=timeperiods');
    ok( $request->is_success, 'get_test_timeperiod() needs a proper config page' ) or diag(Dumper($request));
    my $page = $request->content;
    my $timeperiod;
    if($page =~ m/id="timeperiod_.*?">\s*(<td[^>]+>\s*<i>all<\/i>\s*<\/td>|)\s*<td\ class='dataOdd'>([^<]+)<\/td>/gmxo) {
        $timeperiod = $2;
    }
    isnt($timeperiod, undef, "got a timeperiod from config.cgi") or bail_out_req('got no test config, cannot test.', $request);
    return($timeperiod);
}

#########################
sub get_test_host_cli {
    my($binary) = @_;
    my $auth = '';
    if(!$ENV{'CATALYST_SERVER'}) {
        my $user = Thruk->config->{'cgi_cfg'}->{'default_user_name'};
        $auth = ' -A "'.$user.'"' if($user and $user ne 'thrukadmin');
    }
    my $test = { cmd  => $binary.' -a listhosts'.$auth };
    test_command($test);
    my $host = (split(/\n/mx, $test->{'stdout'}))[0];
    isnt($host, undef, 'got test hosts') or BAIL_OUT($0.": need test host:\n".Dumper($test));
    return $host;
}

#########################
sub get_test_hostgroup_cli {
    my($binary) = @_;
    my $auth = '';
    if(!$ENV{'CATALYST_SERVER'}) {
        my $user = Thruk->config->{'cgi_cfg'}->{'default_user_name'};
        $auth = ' -A "'.$user.'"' if($user and $user ne 'thrukadmin');
    }
    my $test = { cmd  => $binary.' -a listhostgroups'.$auth };
    TestUtils::test_command($test);
    my @groups = split(/\n/mx, $test->{'stdout'});
    my $hostgroup;
    for my $group (@groups) {
        my($name, $members) = split/\s+/, $group, 2;
        next unless $members;
        $hostgroup = $name;
    }
    isnt($hostgroup, undef, 'got test hostgroup') or BAIL_OUT($0.": need test hostgroup");
    return $hostgroup;
}

#########################

=head2 test_page

  check a page

  needs test hash
  {
    url             => url to test
    post            => do post request with this data
    follow          => follow redirects
    fail            => request should fail
    redirect        => request should redirect
    location        => redirect location
    fail_message_ok => page can contain error message without failing
    like            => (list of) regular expressions which have to match page content
    unlike          => (list of) regular expressions which must not match page content
    content_type    => match this content type
    skip_html_lint  => skip html lint check
    skip_doctype    => skip doctype check, even if its an html page
    skip_js_check   => skip js comma check
    sleep           => sleep this amount of seconds after the request
    waitfor         => wait till regex occurs (max 120sec)
    agent           => user agent for requests
    callback        => content callback
  }

=cut
sub test_page {
    my(%opts) = @_;
    my $return = {};

    my $start = time();
    my $opts = _set_test_page_defaults(\%opts);

    # make tests with http://localhost/naemon possible
    my $product = 'thruk';
    if(defined $ENV{'CATALYST_SERVER'} and $ENV{'CATALYST_SERVER'} =~ m|/(\w+)$|mx) {
        $product = $1;
        $opts->{'url'} =~ s|/thruk|/$product|gmx;
    }

    if($opts->{'post'}) {
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Varname = 'POST';
        ok($opts->{'url'}, 'POST '.$opts->{'url'}.' '.Dumper($opts->{'post'}));
    } else {
        ok($opts->{'url'}, 'GET '.$opts->{'url'});
    }

    my $request = _request($opts->{'url'}, $opts->{'startup_to_url'}, $opts->{'post'}, $opts->{'agent'});

    if(defined $opts->{'follow'}) {
        my $redirects = 0;
        while(my $location = $request->{'_headers'}->{'location'}) {
            if($location !~ m/^(http|\/)/gmxo) { $location = _relative_url($location, $request->base()->as_string()); }
            $request = _request($location, undef, undef, $opts->{'agent'});
            $redirects++;
            last if $redirects > 10;
        }
        ok( $redirects < 10, 'Redirect succeed after '.$redirects.' hops' ) or bail_out_req('too many redirects', $request);
    }

    if(!defined $opts->{'fail_message_ok'}) {
        if($request->content =~ m/<span\ class="fail_message">([^<]+)<\/span>/mxo) {
            fail('Request '.$opts->{'url'}.' had error message: '.$1);
        }
    }

    # wait for something?
    $return->{'content'} = $request->content;
    if(defined $opts->{'waitfor'}) {
        my $now = time();
        my $waitfor = $opts->{'waitfor'};
        my $found   = 0;
        while($now < $start + 120) {
            # text that shouldn't appear
            if(defined $opts->{'unlike'}) {
                for my $unlike (@{_list($opts->{'unlike'})}) {
                    if($return->{'content'} =~ m/$unlike/mx) {
                        fail("Content should not contain: ".(defined $1 ? $1 : $unlike)) or diag($opts->{'url'});
                        return $return;
                    }
                }
            }

            if($return->{'content'} =~ m/$waitfor/mx) {
                ok(1, "content ".$waitfor." found after ".($now - $start)."seconds");
                $found = 1;
                last;
            }
            sleep(1);
            $now = time();
            $request = _request($opts->{'url'}, $opts->{'startup_to_url'}, undef, $opts->{'agent'});
            $return->{'content'} = $request->content;
        }
        fail("content did not occur within 120 seconds") unless $found;
        return $return;
    }

    if($request->is_redirect and $request->{'_headers'}->{'location'} =~ m/cgi\-bin\/job\.cgi\?job=(.*)$/mxo) {
        # is it a background job page?
        wait_for_job($1);
        my $location = $request->{'_headers'}->{'location'};
        $request = _request($location, undef, undef, $opts->{'agent'});
        $return->{'content'} = $request->content;
        if($request->is_error) {
            fail('Request '.$location.' should succeed. Original url: '.$opts->{'url'});
            bail_out_req('request failed', $request);
        }
    }
    elsif(defined $opts->{'fail'}) {
        ok( $request->is_error, 'Request '.$opts->{'url'}.' should fail' );
    }
    elsif(defined $opts->{'redirect'}) {
        ok( $request->is_redirect, 'Request '.$opts->{'url'}.' should redirect' ) or diag(Dumper($opts, $request));
        if(defined $opts->{'location'}) {
            if(defined $request->{'_headers'}->{'location'}) {
                like($request->{'_headers'}->{'location'}, qr/$opts->{'location'}/, "Content should redirect: ".$opts->{'location'});
            } else {
                fail('no redirect header found');
            }
        }
    }
    elsif(defined $return->{'content'} and $return->{'content'} =~ m/cgi\-bin\/job\.cgi\?job=(.*)$/mxo) {
        # is it a background job page?
        wait_for_job($1);
        my $location = "/".$product."/cgi-bin/job.cgi?job=".$1;
        $request = _request($location, undef, undef, $opts->{'agent'});
        $return->{'content'} = $request->content;
        if($request->is_error) {
            fail('Request '.$location.' should succeed. Original url: '.$opts->{'url'});
            bail_out_req('request failed', $request);
        }
    } else {
        ok( $request->is_success, 'Request '.$opts->{'url'}.' should succeed' ) or bail_out_req('request failed', $request);
    }

    # text that should appear
    if(defined $opts->{'like'}) {
        for my $like (@{_list($opts->{'like'})}) {
            like($return->{'content'}, qr/$like/, "Content should contain: ".$like) or diag($opts->{'url'});
        }
    }

    # text that shouldn't appear
    if(defined $opts->{'unlike'}) {
        for my $unlike (@{_list($opts->{'unlike'})}) {
            unlike($return->{'content'}, qr/$unlike/, "Content should not contain: ".$unlike) or diag($opts->{'url'});
        }
    }

    # test the content type
    $return->{'content_type'} = $request->header('Content-Type');
    my $content_type = $request->header('Content-Type');
    if(defined $opts->{'content_type'}) {
        is($return->{'content_type'}, $opts->{'content_type'}, 'Content-Type should be: '.$opts->{'content_type'}) or diag($opts->{'url'});
    }


    # memory usage
    SKIP: {
        skip "skipped memory check, set TEST_AUTHOR_MEMORY to enable", 1 unless defined $ENV{'TEST_AUTHOR_MEMORY'};
        my $rsize = Thruk::Utils::get_memory_usage($$);
        ok($rsize < 1024, 'resident size ('.$rsize.'MB) higher than 1024MB on '.$opts->{'url'});
    }

    # html valitidy
    if(!defined $opts->{'skip_doctype'} or $opts->{'skip_doctype'} == 0) {
        if($content_type =~ 'text\/html' and !$request->is_redirect) {
            like($return->{'content'}, '/<html[^>]*>/i', 'html page has html section');
            like($return->{'content'}, '/<!doctype/i',   'html page has doctype');
        }
    }

    SKIP: {
        if($content_type =~ 'text\/html' and (!defined $opts->{'skip_html_lint'} or $opts->{'skip_html_lint'} == 0)) {
            if($use_html_lint == 0) {
                skip "no HTML::Lint installed", 2;
            }
            isa_ok( $lint, "HTML::Lint" );
            $lint->newfile($opts->{'url'});
            # will result in "Parsing of undecoded UTF-8 will give garbage when decoding entities..." otherwise
            my $content = decode_utf8($return->{'content'});
            $lint->parse($content);
            my @errors = $lint->errors;
            @errors = diag_lint_errors_and_remove_some_exceptions($lint);
            is( scalar @errors, 0, "No errors found in HTML" ) or diag($content);
            $lint->clear_errors();
        }
    }

    # check for missing images / css or js
    if($content_type =~ 'text\/html') {
        my $content = $return->{'content'};
        # check for failed javascript lists
        verify_html_js($content) unless $opts->{'skip_js_check'};
        # remove script tags without a src
        $content =~ s/<script[^>]*>.+?<\/script>//gsmxio;
        my @matches1 = $content =~ m/\s+(src|href)='(.+?)'/gio;
        my @matches2 = $content =~ m/\s+(src|href)="(.+?)"/gio;
        my $links_to_check;
        my $x=0;
        for my $match (@matches1, @matches2) {
            $x++;
            next if $x%2==1;
            next if $match =~ m/^http/mxo;
            next if $match =~ m/^ssh/mxo;
            next if $match =~ m/^mailto:/mxo;
            next if $match =~ m/^(\#|'|")/mxo;
            next if $match =~ m/^\/$product\/cgi\-bin/mxo;
            next if $match =~ m/^\w+\.cgi/mxo;
            next if $match =~ m/^javascript:/mxo;
            next if $match =~ m/^'\+\w+\+'$/mxo         and defined $ENV{'CATALYST_SERVER'};
            next if $match =~ m|^/$product/frame\.html|mxo and defined $ENV{'CATALYST_SERVER'};
            next if $match =~ m/"\s*\+\s*icon\s*\+\s*"/mxo;
            next if $match =~ m/\/"\+/mxo;
            next if $match =~ m/data:image\/png;base64/mxo;
            $match =~ s/"\s*\+\s*url_prefix\s*\+\s*"/\//gmxo;
            $match =~ s/"\s*\+\s*theme\s*\+\s*"/Thruk/gmxo;
            $links_to_check->{$match} = 1;
        }
        my $errors = 0;
        for my $test_url (keys %{$links_to_check}) {
            next if $test_url =~ m/\/pnp4nagios\//mxo;
            next if $test_url =~ m/\/pnp\//mxo;
            next if $test_url =~ m|/$product/themes/.*?/images/logos/|mxo;
            if($test_url !~ m/^(http|\/)/gmxo) { $test_url = _relative_url($test_url, $request->base()->as_string()); }
            my $request = _request($test_url, undef, undef, $opts->{'agent'});

            if($request->is_redirect) {
                my $redirects = 0;
                while(my $location = $request->{'_headers'}->{'location'}) {
                    if($location !~ m/^(http|\/)/gmxo) { $location = _relative_url($location, $request->base()->as_string()); }
                    $request = _request($location, undef, undef, $opts->{'agent'});
                    $redirects++;
                    last if $redirects > 10;
                }
            }
            unless($request->is_success) {
                $errors++;
                diag("'$test_url' is missing, status: ".$request->code);
            }
        }
        is( $errors, 0, 'All stylesheets, images and javascript exist' );
    }

    # sleep after the request?
    if(defined $opts->{'sleep'}) {
        ok(sleep($opts->{'sleep'}), "slept $opts->{'sleep'} seconds");
    }

    if($opts->{'callback'}) {
        $opts->{'callback'}($return->{'content'});
    }

    return $return;
}

#########################

=head2 set_cookie

    set_cookie($name, $value, $expire)

  Sets cookie. Expire date is in seconds. A value <= 0 will remove the cookie.

=cut
sub set_cookie {
    my($var, $val, $expire) = @_;
    our($cookie_jar, $cookie_file);
    if(!defined $cookie_jar) {
        my $fh;
        ($fh, $cookie_file) = tempfile(TEMPLATE => 'tempXXXXX', UNLINK => 1);
        unlink ($cookie_file);
        $cookie_jar = HTTP::Cookies::Netscape->new(file => $cookie_file);
    }
    my $config = Thruk::Backend::Pool::get_config();
    my $cookie_path = $config->{'cookie_path'};
    $cookie_jar->set_cookie( 0, $var, $val, $cookie_path, 'localhost.local', undef, 1, 0, $expire, 1, {});
    $cookie_jar->save();
    return;
}

#########################
sub diag_lint_errors_and_remove_some_exceptions {
    my $lint = shift;
    my @return;
    for my $error ( $lint->errors ) {
        my $err_str = $error->as_string;
        next if $err_str =~ m/<IMG\ SRC=".*command.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*warning.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*unknown.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*critical.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*flapping.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*recovery.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*restart.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*start.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*icon_minimize\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*right\.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*left\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*right\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*up\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*down\.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*down\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*json\.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*waiting\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*downtime\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*info\.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*problem\.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*criticity_\d\.png">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*stop\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*notify\.gif">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;

        next if $err_str =~ m/<IMG\ SRC=".*\/conf\/images\/obj_.*">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC=".*\/logos\/.*">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC="[^"]*\.cgi[^"]*">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/<IMG\ SRC="data:image[^"]*">\ tag\ has\ no\ HEIGHT\ and\ WIDTH\ attributes/imxo;
        next if $err_str =~ m/Unknown\ attribute\ "data\-\w+"\ for\ tag/imxo;
        next if $err_str =~ m/Invalid\ character.*should\ be\ written\ as/imxo;
        next if $err_str =~ m/Unknown\ attribute\ "placeholder"\ for\ tag\ <input>/imxo;
        next if $err_str =~ m/Unknown\ attribute\ "class"\ for\ tag\ <html>/imxo;
        next if $err_str =~ m/Unknown\ attribute\ "autocomplete"\ for\ tag\ <form>/imxo;
        next if $err_str =~ m/Unknown\ attribute\ "autocomplete"\ for\ tag\ <input>/imxo;
        next if $err_str =~ m/Character\ ".*?"\ should\ be\ written\ as/imxo;
        next if $err_str =~ m/Unknown\ attribute\ "manifest"\ for\ tag\ <html>/imxo;
        diag($error->as_string."\n");
        push @return, $error;
    }
    return @return;
}

#########################
sub get_themes {
    my @themes = @{Thruk->config->{'View::TT'}->{'PRE_DEFINE'}->{'themes'}};
    return @themes;
}

#########################
sub get_c {
    our($c);
    return $c if defined $c;
    my $res;
    ($res, $c) = ctx_request('/thruk/side.html');
    return $c;
}

#########################
sub get_user {
    my $c = get_c();
    my ($uid, $groups) = Thruk::Utils::get_user($c);
    my $user           = getpwuid($uid);
    return $user;
}

#########################
sub wait_for_job {
    my $job = shift;
    my $start  = time();
    my $config = Thruk::Backend::Pool::get_config();
    my $jobdir = $config->{'var_path'} ? $config->{'var_path'}.'/jobs/'.$job : './var/jobs/'.$job;
    if(!-e $jobdir) {
        fail("job folder ".$jobdir.": ".$!);
        return;
    }
    local $SIG{ALRM} = sub { die("timeout while waiting for job: ".$jobdir) };
    alarm(120);
    eval {
        while(Thruk::Utils::External::_is_running($jobdir)) {
            sleep(1);
        }
    };
    alarm(0);
    my $end  = time();
    is(Thruk::Utils::External::_is_running($jobdir), 0, 'job is finished in '.($end-$start).' seconds')
        or diag(sprintf("uptime: %s\n\nps:\n%s\n\njobs:\n%s\n",
                            scalar `uptime`,
                            scalar `ps -efl`,
                            scalar `find $jobdir/ -ls -exec cat {} \\;`,
               ));
    return;
}

#########################

=head2 test_command

  execute a test command

  needs test hash
  {
    cmd     => command line to execute
    exit    => expected exit code
    like    => (list of) regular expressions which have to match stdout
    errlike => (list of) regular expressions which have to match stderr, default: empty
    sleep   => time to wait after executing the command
  }

=cut
sub test_command {
   my $test = shift;
    my($rc, $stderr) = ( -1, '') ;
    my $return = 1;

    require Test::Cmd;
    Test::Cmd->import();

    # run the command
    isnt($test->{'cmd'}, undef, "running cmd: ".$test->{'cmd'}) or $return = 0;

    my($prg,$arg) = split(/\s+/, $test->{'cmd'}, 2);
    my $t = Test::Cmd->new(prog => $prg, workdir => '') or die($!);
    alarm(300);
    eval {
        local $SIG{ALRM} = sub { die "timeout on cmd: ".$test->{'cmd'}."\n" };
        $t->run(args => $arg, stdin => $test->{'stdin'});
        $rc = $?>>8;
    };
    if($@) {
        $stderr = $@;
    } else {
        $stderr = $t->stderr;
    }
    alarm(0);

    # exit code?
    $test->{'exit'} = 0 unless exists $test->{'exit'};
    if(defined $test->{'exit'} and $test->{'exit'} != -1) {
        ok($rc == $test->{'exit'}, "exit code: ".$rc." == ".$test->{'exit'}) or do { diag("command failed with rc: ".$rc." - ".$t->stdout); $return = 0 };
    }

    # matches on stdout?
    if(defined $test->{'like'}) {
        for my $expr (@{_list($test->{'like'})}) {
            like($t->stdout, $expr, "stdout like ".$expr) or do { diag("\ncmd: '".$test->{'cmd'}."' failed\n"); $return = 0 };
        }
    }

    # matches on stderr?
    $test->{'errlike'} = '/^\s*$/' unless exists $test->{'errlike'};
    if(defined $test->{'errlike'}) {
        for my $expr (@{_list($test->{'errlike'})}) {
            like($stderr, $expr, "stderr like ".$expr) or do { diag("\ncmd: '".$test->{'cmd'}."' failed"); $return = 0 };
        }
    }

    # sleep after the command?
    if(defined $test->{'sleep'}) {
        ok(sleep($test->{'sleep'}), "slept $test->{'sleep'} seconds") or do { $return = 0 };
    }

    # set some values
    $test->{'stdout'} = $t->stdout;
    $test->{'stderr'} = $t->stderr;
    $test->{'exit'}   = $rc;

    return $return;
}

#########################

=head2 overrideConfig

    overrideConfig('key', 'value')

  override config setting

=cut
sub overrideConfig {
    my($key, $value) = @_;
    my $c = get_c();
    $c->config->{$key} = $value;
    ok(1, "config: set '$key' to '$value'");
    return;
}

#########################
sub make_test_hash {
    my $data = shift;
    my $test = shift || {};
    if(ref $data eq '') {
        $test->{'url'} = $data;
    } else {
        for my $key (%{$data}) {
            $test->{$key} = $data->{$key};
        }
    }
    return $test;
}
#########################
sub _relative_url {
    my($location, $url) = @_;
    my $newloc = $url;
    $newloc    =~ s/^(.*\/).*$/$1/gmxo;
    $newloc    .= $location;
    while($newloc =~ s|/[^\/]+/\.\./|/|gmxo) {}
    return $newloc;
}

#########################
sub _request {
    my($url, $start_to, $post, $agent) = @_;

    our($cookie_jar, $cookie_file);
    if(!defined $cookie_jar) {
        my $fh;
        ($fh, $cookie_file) = tempfile(TEMPLATE => 'tempXXXXX', UNLINK => 1);
        unlink ($cookie_file);
        $cookie_jar = HTTP::Cookies::Netscape->new(file => $cookie_file);
    }

    if(defined $ENV{'CATALYST_SERVER'}) {
        return(_external_request(@_));
    }
    $url = 'http://localhost.local'.$url;

    my $response;
    if($post) {
        $post->{'token'} = 'test';
        my $request = POST($url, [%{$post}]);
        $cookie_jar->add_cookie_header($request);
        $request->header("User-Agent" => $agent) if $agent;
        $response = request($request);
    } else {
        my $request = HTTP::Request->new(GET => $url);
        $request->header("User-Agent" => $agent) if $agent;
        $cookie_jar->add_cookie_header($request);
        $response = request($request);
    }
    $cookie_jar->extract_cookies($response);
    $response      = _check_startup_redirect($response, $start_to);

    return $response;
}

#########################
sub _external_request {
    my($url, $start_to, $post, $agent, $retry) = @_;
    $retry = 1 unless defined $retry;

    # make tests with http://localhost/naemon possible
    unless($url =~ m/^http/) {
        my $product = 'thruk';
        if($ENV{'CATALYST_SERVER'} =~ m|/(\w+)$|mx) {
            $product = $1;
            $url =~ s|/$product/|/|gmx;
            $url =~ s|/thruk/|/|gmx;
        }
        $url =~ s#//#/#gmx;
        $url = $ENV{'CATALYST_SERVER'}.$url;
    }

    our($cookie_jar, $cookie_file);
    my $ua = LWP::UserAgent->new(
        keep_alive   => 1,
        max_redirect => 0,
        timeout      => 30,
        requests_redirectable => [],
    );
    $ua->env_proxy;
    $ua->cookie_jar($cookie_jar);
    $ua->agent( $agent ) if $agent;

    if($post and ref $post ne 'HASH') {
        confess("unknown post data: ".Dumper($post));
    }
    my $req;
    if($post) {
        $post->{'token'} = 'test';
        $req = $ua->post($url, $post);
    } else {
        $req = $ua->get($url);
    }

    $req = _check_startup_redirect($req, $start_to);

    if($req->is_redirect and $req->{'_headers'}->{'location'} =~ m/\/(thruk|naemon)\/cgi\-bin\/login\.cgi\?(.*)$/mxo and defined $ENV{'THRUK_TEST_AUTH'}) {
        die("login failed: ".Dumper($req)) unless $retry;
        my $product = $1;
        my($user, $pass) = split(/:/mx, $ENV{'THRUK_TEST_AUTH'}, 2);
        my $r = _external_request('/'.$product.'/cgi-bin/login.cgi', undef, undef, $agent);
           $r = _external_request('/'.$product.'/cgi-bin/login.cgi', undef, { password => $pass, login => $user, submit => 'login' }, $agent, 0);
        $req  = _external_request($url, $start_to, $post, $agent, 0);
    }
    return $req;
}

#########################
sub _check_startup_redirect {
    my($request, $start_to) = @_;
    if($request->is_redirect and $request->{'_headers'}->{'location'} =~ m/\/(thruk|naemon)\/startup\.html\?(.*)$/mxo) {
        my $product = $1;
        my $link    = $2;
        $link    =~ s/^wait\#//mxo;
        #diag("starting up... ".$link);
        is($link, $start_to, "startup url points to: ".$link) if defined $start_to;
        # startup fcgid
        my $r = _request('/'.$product.'/cgi-bin/remote.cgi', undef, {});
        #diag("startup request:");
        #diag(Dumper($r));
        fail("startup failed: ".Dumper($r)) unless $r->is_success;
        fail("startup failed, no pid: ".Dumper($r)) unless(-f '/var/cache/thruk/thruk.pid' || -f '/var/cache/naemon/thruk/thruk.pid');
        sleep(3);
        if($link !~ m/\?/mx && $link =~ m/\&/mx) { $link =~ s/\&/?/mx; }
        $request = _request($link);
        #diag("original request:");
        #diag(Dumper($request));
    }
    return($request);
}

#########################
sub _set_test_page_defaults {
    my($opts) = @_;
    if(!exists $opts->{'unlike'}) {
        $opts->{'unlike'} = [ 'internal server error', 'HASH', 'ARRAY' ];
    }
    return $opts;
}

#########################
sub bail_out_req {
    my($msg, $req) = @_;
    my $page    = $req->content;
    my $error   = "";
    if($page =~ m/<!--error:(.*?):error-->/smx) {
        $error = $1;
        $error =~ s/\A\s*//gmsx;
        $error =~ s/\s*\Z//gmsx;
        BAIL_OUT($0.': '.$req->code.' '.$msg.' - '.$error);
    }
    if($page =~ m/<pre\s+id="error">(.*)$/mx) {
        $error = HTML::Entities::decode($1);
        $error =~ s|</pre>$||gmx;
        BAIL_OUT($0.': '.$req->code.' '.$msg.' - '.$error);
    }
    diag(Dumper($msg));
    diag(Dumper($req));
    BAIL_OUT($0.': '.$msg);
    return;
}

#########################
sub set_test_user_token {
    require Thruk::Config;
    require Thruk::Utils::Cache;
    my $config = Thruk::Config::get_config();
    my $store  = Thruk::Utils::Cache->new($config->{'var_path'}.'/token');
    my $tokens = $store->get('token');
    $tokens->{get_test_user()} = { token => 'test', time => time() };
    $store->set('token', $tokens);
    return;
}

#########################
sub _list {
    my($data) = @_;
    return $data if ref $data eq 'ARRAY';
    return([$data]);
}

#################################################
# verify js syntax
sub verify_js {
    my($file) = @_;
    return if $file =~ m/jit-yc.js/gmx;
    return if $file =~ m/jquery.mobile.router/gmx;
    my $content = read_file($file);
    my $matches = _replace_with_marker($content);
    return unless scalar $matches > 0;
    _check_marker($file, $content);
    return;
}

#################################################
# verify js syntax in html
sub verify_html_js {
    my($content) = @_;
    $content =~ s/(<script.*?<\/script>)/&_extract_js($1)/misge;
    _check_marker(undef, $content);
    return;
}

#################################################
# verify js syntax in templates
sub verify_tt {
    my($file) = @_;
    my $content = read_file($file);
    $content =~ s/(<script.*?<\/script>)/&_extract_js($1)/misge;
    _check_marker($file, $content);
    return;
}

#################################################
# verify js syntax in templates
sub _extract_js {
    my($text) = @_;
    _replace_with_marker($text);
    return $text;
}

#################################################
# verify js syntax in templates
sub _replace_with_marker {
    my $errors  = 0;

    # trailing commas
    my @matches = $_[0]  =~ s/(\,\s*[\)|\}|\]])/JS_ERROR_MARKER1:$1/sgmxi;
    $errors    += scalar @matches;

    # insecure for loops which do not work in IE8
    @matches = $_[0]  =~ s/(for\s*\(.*\s+in\s+.*\))/JS_ERROR_MARKER2:$1/gmxi;
    # for(var key in... is ok
    @matches = grep {!/var\s+key/} @matches;
    $errors    += scalar @matches;

    # jQuery().attr('checked', true) must be .prop now
    @matches = $_[0]  =~ s/(\.attr\s*\(.*checked)/JS_ERROR_MARKER3:$1/gmxi;
    $errors    += scalar @matches;

    return $errors;
}

#################################################
sub _check_marker {
    my($file, $content) = @_;
    my @lines = split/\n/mx, $content;
    my $x = 1;
    for my $line (@lines) {
        if($line =~ m/JS_ERROR_MARKER1:/mx) {
            my $orig = $line;
            $orig   .= "\n".$lines[$x+1] if defined $lines[$x+1];
            $orig =~ s/JS_ERROR_MARKER1://gmx;
            fail('found trailing comma in '.($file || 'content').' line: '.$x);
            diag($orig);
        }
        if($line =~ m/JS_ERROR_MARKER2:/mx and $line !~ m/var\s+key/) {
            my $orig = $line;
            $orig =~ s/JS_ERROR_MARKER2://gmx;
            fail('found insecure for loop in '.($file || 'content').' line: '.$x);
            diag($orig);
        }
        if($line =~ m/JS_ERROR_MARKER3:/mx) {
            my $orig = $line;
            $orig   .= "\n".$lines[$x+1] if defined $lines[$x+1];
            $orig =~ s/JS_ERROR_MARKER3://gmx;
            fail('found jQuery.attr(checked) instead of .prop() in '.($file || 'content').' line: '.$x);
            diag($orig);
        }
        $x++;
    }
}

#################################################
END {
    our $cookie_file;
    unlink($cookie_file) if defined $cookie_file;
}

#################################################

1;

__END__
