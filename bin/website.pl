#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Dancer;
use DBI;
use FindBin;
use File::Spec::Functions qw(catdir);
use Cwd 'abs_path';

my $APP_DIR = abs_path(catdir($FindBin::Bin, '..'));
set appdir => $APP_DIR;
chdir $APP_DIR;


my $dbh = DBI->connect('dbi:SQLite:dbname=queue.db', '', '');
$dbh->do(qq{
    CREATE TABLE IF NOT EXISTS queue (
        id     INTEGER PRIMARY KEY AUTOINCREMENT,
        url    TEXT NOT NULL,
        size   TEXT NOT NULL DEFAULT '1280x800',
        type   TEXT NOT NULL DEFAULT 'png',
        proxy  TEXT NOT NULL DEFAULT '',
        xpath  TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending'
    );
});

get '/' => sub {

    my $url = param('url') // '';
    my $id = param('id') // 0;
    my $size = param('size') // '1280x800';
    my $proxy = param('proxy') // '';
    my $xpath = param('xpath') // '';
    my $type = param('type') // 'pdf';

    my $select = $dbh->prepare("SELECT * FROM queue");
    $select->execute();

    my @rows;
    while (my $row = $select->fetchrow_hashref) {
        my $status_text = $row->{status};

        push @rows, $row;
    }

    my $data = {
        rows  => \@rows,
        url   => $url,
        id    => $id,
        type  => $type,
        size  => $size,
        proxy => $proxy,
        xpath => $xpath,
    };

    return template 'index.html', $data;
};


get '/add' => sub {
    my $url = param('url') or return do_error("Missing parameter 'url'");
    my $size = param('size') // '';
    my $type = param('type') // 'png';
    my $proxy = param('proxy') // '';
    my $xpath = param('xpath') // '';

    foreach my $val ($url, $size, $type, $proxy, $xpath) {
        $val = trim($val);
    }

    $dbh->begin_work();

    my $id = '';
    eval {
        $dbh->do(
            "INSERT INTO queue (url, size, type, proxy, xpath) VALUES (?, ?, ?, ?, ?)",
            undef,
            $url, $size, $type, $proxy, $xpath,
        );
        $id = $dbh->sqlite_last_insert_rowid();
        $dbh->commit();
        1;
    } or do {
        my $error = $@ || "Internal error";
        warn "Error: $error";
        $dbh->rollback();
        return send_error "Server error";
    };

    return redirect "/?id=$id";
};


get '/delete' => sub {
    my $id = param('id') or return do_error("Missing parameter 'id'");

    $dbh->begin_work();

    eval {
        $dbh->do("DELETE FROM queue WHERE id = ?", undef, $id);
        $dbh->commit();
        1;
    } or do {
        my $error = $@ || "Internal error";
        warn "Error: $error";
        $dbh->rollback();
        return send_error "Server error";
    };

    return redirect "/";
};


my %MIME_TYPES = (
    pdf => 'application/pdf',
    png => 'image/png',
);
get '/view' => sub {
    my $id = param('id') or return do_error("Missing parameter 'id'");
 
    my $select = $dbh->prepare("SELECT type FROM queue WHERE id = ? LIMIT 1");
    $select->execute($id);
    while (my $row = $select->fetchrow_hashref) {
        my $type = $row->{type} || 'png';
        my $file = "captures/$id.$type";
        my $mime_type = $MIME_TYPES{$type};
        debug "Showing $file ($mime_type)";
        return do_error("Can't find the file $file") unless -e $file;
        return send_file $file, content_type => $mime_type, system_path => 1;
    }

    return do_error("Can't find screenshot with id: $id");
};


sub do_error {
    my ($message) = @_;
    return qq{
        <html>
        <body>
        <h1>Error</h1>
        <p>$message</p>
        </body>
        </html>
    };
}


sub trim {
    my ($string) = @_;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}


dance();
