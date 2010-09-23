#!/usr/bin/env perl
use strict;

package Errcount;
use DBI;

my $config;
sub config {
    $config = $_[1] if @_ == 2;
    return $config;
}

sub get {
    my ($class, $site) = @_;

    my $dbh = DBI->connect(@{ $class->config });

    my $record = $dbh->selectrow_hashref("SELECT * from counters WHERE host = ?", undef, $site);

    if ($record && $record->{hits}) {
        $dbh->do("UPDATE counters SET hits = ? WHERE host = ?", undef, $record->{hits} + 1, $site);

        return $record->{hits} + 1;
    }

    my $sqlh = $dbh->prepare("INSERT INTO counters (host, hits) VALUES (?, 1)");
    $sqlh->execute($site);
    return 1;
}

package main;
use Plack;
use Plack::Request;
use Plack::Builder;

use URI;
use JSON;
my $json = JSON->new;
$json->allow_nonref(1);

if (-f "database.json") {
    local $\ = undef;
    open my $fh, "<", "database.json";
    my $config = <$fh>;
    close($fh);

    my $json = JSON->new;
    $config = $json->decode($config);

    Errcount->config($config);
}
else {
    die "database.json is missing\n";
}

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $count = int(rand(1048576)) - 524288;

    if ($env->{'HTTP_REFERER'}) {
        my $uri = URI->new($env->{'HTTP_REFERER'});
        my $site = $uri->host;

        $count = Errcount->get($site);
    }

    my $res = $req->new_response(200);
    $res->content_type("text/javascript");
    $res->body("document.write(@{[ $json->encode($count) ]});\n");
    $res->finalize;
};

builder {
    enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' } "Plack::Middleware::ReverseProxy";
    $app;
};

$app;

__END__

CREATE TABLE `counters` (
    `host` varchar(255) NOT NULL PRIMARY KEY,
    `hits` integer unsigned DEFAULT '1'
) DEFAULT CHARSET=utf8;
