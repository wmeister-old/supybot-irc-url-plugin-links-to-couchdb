package Mojolicious::Command::get;
use Mojo::Base 'Mojolicious::Command';

use Mojo::DOM;
use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::JSON::Pointer;
use Mojo::UserAgent;
use Mojo::Util qw(decode encode);

has description => "Perform HTTP request.\n";
has usage       => <<"EOF";
usage: $0 get [OPTIONS] URL [SELECTOR|JSON-POINTER] [COMMANDS]

  mojo get /
  mojo get mojolicio.us
  mojo get -v -r google.com
  mojo get -M POST -c 'trololo' mojolicio.us
  mojo get -H 'X-Bender: Bite my shiny metal ass!' mojolicio.us
  mojo get mojolicio.us 'head > title' text
  mojo get mojolicio.us .footer all
  mojo get mojolicio.us a attr href
  mojo get mojolicio.us '*' attr id
  mojo get mojolicio.us 'h1, h2, h3' 3 text
  mojo get http://search.twitter.com/search.json /error

These options are available:
  -C, --charset <charset>     Charset of HTML5/XML content, defaults to auto
                              detection or "UTF-8".
  -c, --content <content>     Content to send with request.
  -H, --header <name:value>   Additional HTTP header.
  -M, --method <method>       HTTP method to use, defaults to "GET".
  -r, --redirect              Follow up to 10 redirects.
  -v, --verbose               Print request and response headers to STDERR.
EOF

# "Objection.
#  In the absence of pants, defense's suspenders serve no purpose.
#  I'm going to allow them... for now."
sub run {
  my ($self, @args) = @_;

  # Options
  $self->_options(
    \@args,
    'C|charset=s' => \my $charset,
    'c|content=s' => \(my $content = ''),
    'H|header=s'  => \my @headers,
    'M|method=s'  => \(my $method = 'GET'),
    'r|redirect'  => \my $redirect,
    'v|verbose'   => \my $verbose
  );
  $verbose = 1 if $method eq 'HEAD';

  # Headers
  my %headers;
  /^\s*([^:]+)\s*:\s*([^:]+)\s*$/ and $headers{$1} = $2 for @headers;

  # URL and selector
  die $self->usage unless my $url = decode 'UTF-8', shift @args // '';
  my $selector = shift @args;

  # Fresh user agent
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
  $ua->max_redirects(10) if $redirect;

  # Absolute URL
  if ($url !~ m!/!) { $ua->detect_proxy }

  # Application
  else { $ua->app($self->app) }

  # Start
  my $v = my $buffer = '';
  $ua->on(
    start => sub {
      my $tx = pop;

      # Prepare request information
      my $req         = $tx->req;
      my $startline   = $req->build_start_line;
      my $req_headers = $req->build_headers;

      # Verbose callback
      my $v  = $verbose;
      my $cb = sub {
        my $res = shift;

        # Wait for headers
        return unless $v && $res->headers->is_finished;

        # Request
        warn "$startline$req_headers";

        # Response
        my $version     = $res->version;
        my $code        = $res->code;
        my $message     = $res->message;
        my $res_headers = $res->headers->to_string;
        warn "HTTP/$version $code $message\n$res_headers\n\n";

        # Finished
        $v = undef;
      };

      # Progress
      $tx->res->on(progress => $cb);

      # Stream content
      $tx->res->body(
        sub {
          $cb->(my $res = shift);

          # Ignore intermediate content
          return if $redirect && $res->is_status_class(300);

          # Chunk
          $selector ? ($buffer .= pop) : print(pop);
        }
      );
    }
  );

  # Get
  STDOUT->autoflush(1);
  my $tx = $ua->start($ua->build_tx($method, $url, \%headers, $content));

  # Error
  my ($message, $code) = $tx->error;
  $url = encode 'UTF-8', $url;
  warn qq{Problem loading URL "$url". ($message)\n} if $message && !$code;

  # JSON Pointer
  return unless $selector;
  my $type = $tx->res->headers->content_type || '';
  return _json($buffer, $selector) if $type =~ /json/i;

  # Selector
  _select($buffer, $selector, $charset // $tx->res->content->charset, @args);
}

sub _json {
  my $json = Mojo::JSON->new;
  return unless my $data = $json->decode(shift);
  return unless defined($data = Mojo::JSON::Pointer->new->get($data, shift));
  ref $data ~~ [qw(HASH ARRAY)] ? say($json->encode($data)) : _say($data);
}

sub _say {
  return unless length(my $value = shift);
  say encode('UTF-8', $value);
}

sub _select {
  my ($buffer, $selector, $charset, @args) = @_;

  # Find
  my $dom     = Mojo::DOM->new->charset($charset)->parse($buffer);
  my $results = $dom->find($selector);

  # Commands
  my $finished;
  while (defined(my $command = shift @args)) {

    # Number
    if ($command =~ /^\d+$/) {
      return unless ($results = [$results->[$command]])->[0];
      next;
    }

    # Text
    elsif ($command eq 'text') { _say($_->text) for @$results }

    # All text
    elsif ($command eq 'all') { _say($_->all_text) for @$results }

    # Attribute
    elsif ($command eq 'attr') {
      next unless my $name = shift @args;
      _say($_->attrs->{$name}) for @$results;
    }

    # Unknown
    else { die qq{Unknown command "$command".\n} }
    $finished++;
  }

  # Render
  unless ($finished) { _say($_) for @$results }
}

1;

=head1 NAME

Mojolicious::Command::get - Get command

=head1 SYNOPSIS

  use Mojolicious::Command::get;

  my $get = Mojolicious::Command::get->new;
  $get->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::get> is a command interface to L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojolicious::Command::get> performs requests to remote hosts or local
applications.

=head2 C<description>

  my $description = $get->description;
  $get            = $get->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $get->usage;
  $get      = $get->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::get> inherits all methods from L<Mojolicious::Command>
and implements the following new ones.

=head2 C<run>

  $get->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
