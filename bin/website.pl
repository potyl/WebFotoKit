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


sub get_queue_item_params {
    my %queue_item = (
        url   => param('url')   // '',
        size  => param('size')  // '1280x800',
        proxy => param('proxy') // '',
        xpath => param('xpath') // '',
        type  => param('type')  // 'png',
    );
 
    foreach my $value (values %queue_item) {
        $value = trim($value);
    }

    return \%queue_item;
}


sub get_queue {
    my $select = $dbh->prepare("SELECT * FROM queue");
    $select->execute();

    my @queue;
    while (my $row = $select->fetchrow_hashref) {
        push @queue, $row;
    }

    return @queue;
}


get '/' => sub {
    my $id    = param('id') // 0;

    my @queue = get_queue();
    my $data = {
        id         => $id,
        queue      => \@queue,
        queue_item => get_queue_item_params(),
    };

    return template 'index.html', $data;
};


get '/add' => sub {
    my $data = {};
    my $queue_item = get_queue_item_params();
    if (! $queue_item->{url}) {
        $data->{queue_item} = $queue_item;
        $data->{queue} = [ get_queue() ];
        $queue_item->{url_error} = "Field can't be empty";
        return do_error('index.html', undef, $data);
    }

    $dbh->begin_work();

    my $id = '';
    eval {
        $dbh->do(
            "INSERT INTO queue (url, size, type, proxy, xpath) VALUES (?, ?, ?, ?, ?)",
            undef,
            @$queue_item{ qw(url size type proxy xpath) },
        );
        $id = $dbh->sqlite_last_insert_rowid();
        $dbh->commit();
        1;
    } or do {
        my $error = $@ || "Internal error";
        warn "Error: $error";
        $dbh->rollback();
        $data->{queue} = [ get_queue() ];
        return do_error('index.html', html("Error: $error"), $data);
    };

    return redirect "/?id=$id";
};


get '/delete' => sub {
    debug "in delete";
    my $id = param('id') or return do_error("index.html", "Invalid parameter <code>id</code>");
    debug "doing delete...";

    $dbh->begin_work();

    my $item;
    eval {
        $item = fetch_queue_item($id);
        $dbh->do("DELETE FROM queue WHERE id = ?", undef, $id);
        $dbh->commit();
        1;
    } or do {
        my $error = $@ || "Internal error";
        warn "Error: $error";
        $dbh->rollback();
        return do_error("index.html", html("Error: $error"));
    };

    unlink $item->{file} if $item and defined $item->{file};

    return redirect "/";
};


get '/about.html' => sub {
    return template 'about.html';
};

my %MIME_TYPES = (
    pdf => 'application/pdf',
    png => 'image/png',
);
sub fetch_queue_item {
    my ($id) = @_;

    my $select = $dbh->prepare("SELECT type FROM queue WHERE id = ? LIMIT 1");
    $select->execute($id);
    while (my $row = $select->fetchrow_hashref) {
        my $type = $row->{type} || 'png';
        $row->{file} = "captures/$id.$type";
        $row->{mime_type} = $MIME_TYPES{$type};
        return $row;
    }

    return undef;
}


get '/view' => sub {
    my $id = param('id') or return do_error("index.html", "Missing parameter <code>id</code>");
    my $item = fetch_queue_item($id) or do_error("index.html", html("Can't find screenshot with id: $id"));

    my $file = $item->{file};
    my $mime_type = $item->{mime_type};
    debug "Showing $file ($mime_type)";

    if (-e $file) {
        return send_file $file, content_type => $mime_type, system_path => 1;
    }
    return do_error("index.html", "Can't find the file <code>" . html($file) . "</code>") unless -e $file;
};


sub do_error {
    my ($template, $error_html, $data) = @_;
    
    $data ||= {};
    $data->{error_html} = $error_html;
    $data->{queue} ||= [ get_queue() ];

    return template $template, $data;
}


sub trim {
    my ($string) = @_;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}


sub html {
    my ($string) = @_;
    $string =~ s/&/&amp;/g;
    $string =~ s/</&lt;/g;
    $string =~ s/>/&gt;/g;
    return $string;
}

dance();
