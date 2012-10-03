#!/usr/bin/env perl


use strict;
use warnings;

use Data::Dumper;
use DBI;
use FindBin;
use File::Spec::Functions qw(catdir catfile);
use Cwd 'abs_path';
use YAML 'LoadFile';

my $APP_DIR = abs_path(catdir($FindBin::Bin, '..'));

sub main {
    chdir $APP_DIR;
    my $conf = LoadFile('config.yml')->{app};

    my $dbh = DBI->connect($conf->{dbi}{dsn}, $conf->{dbi}{login}, $conf->{dbi}{password});

    my $update = $dbh->prepare("UPDATE queue SET status = ? WHERE id = ?");

    $dbh->begin_work();

    my $select = $dbh->prepare("SELECT * FROM queue WHERE status = 'pending' LIMIT 1");
    $select->execute();
    while (my $row = $select->fetchrow_hashref) {
        my $id = $row->{id};
        my $url = $row->{url};

        print "Marking $id as downloading\n";
        $update->execute('downloading', $id);
        $dbh->commit();

        print "Capturing $url as $id.png\n";

        my $file = catfile($conf->{screenshot}{folder}, "$id.$row->{type}");
        my @command = (
            'bin/screenshot.pl', $url,
            '--output', $file,
        );
        foreach my $field ( qw(size type proxy xpath pause) ) {
            my $value = $row->{$field};
            push @command, "--$field", $value if $value;
        }

        print "Running @command\n";
        my $exit = system @command;
        my $status = $exit == 0 ? 'done' : 'error';
        print "Marking $id as $status\n";
        $update->execute($status, $id);
    }

    $dbh->disconnect();


    return 0;
}


exit main() unless caller;
