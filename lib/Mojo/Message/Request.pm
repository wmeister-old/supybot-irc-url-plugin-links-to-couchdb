package Mojo::Message::Request;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Request;
use Mojo::Parameters;
use Mojo::Util qw(b64_encode b64_decode get_line);
use Mojo::URL;

has env => sub { {} };
has method => 'GET';
has url => sub { Mojo::URL->new };

my $START_LINE_RE = qr|
  ^\s*
  ([a-zA-Z]+)                                  # Method
  \s+
  ([0-9a-zA-Z\-._~:/?#[\]\@!\$&'()*+,;=\%]+)   # Path
  (?:\s+HTTP/(\d\.\d))?                        # Version
  $
|x;

sub clone {
  my $self = shift;

  # Dynamic requests cannot be cloned
  return unless my $content = $self->content->clone;
  my $clone = $self->new(
    content => $content,
    method  => $self->method,
    url     => $self->url->clone,
    version => $self->version
  );
  $clone->{proxy} = $self->{proxy}->clone if $self->{proxy};

  return $clone;
}

sub cookies {
  my $self = shift;

  # Parse cookies
  my $headers = $self->headers;
  return [map { @{Mojo::Cookie::Request->parse($_)} } $headers->cookie]
    unless @_;

  # Add cookies
  my @cookies = $headers->cookie || ();
  for my $cookie (@_) {
    $cookie = Mojo::Cookie::Request->new($cookie) if ref $cookie eq 'HASH';
    push @cookies, $cookie;
  }
  $headers->cookie(join('; ', @cookies));

  return $self;
}

sub extract_start_line {
  my ($self, $bufferref) = @_;

  # Ignore any leading empty lines
  $$bufferref =~ s/^\s+//;
  return unless defined(my $line = get_line $bufferref);

  # We have a (hopefully) full request line
  $self->error('Bad request start line', 400) and return
    unless $line =~ $START_LINE_RE;
  my $url = $self->method($1)->version($3)->url;
  return !!($1 eq 'CONNECT' ? $url->authority($2) : $url->parse($2));
}

sub fix_headers {
  my $self = shift;
  $self->{fix} ? return $self : $self->SUPER::fix_headers(@_);

  # Basic authentication
  my $url     = $self->url;
  my $headers = $self->headers;
  if ((my $userinfo = $url->userinfo) && !$headers->authorization) {
    $headers->authorization('Basic ' . b64_encode($userinfo, ''));
  }

  # Proxy
  if (my $proxy = $self->proxy) {
    $url = $proxy if $self->method eq 'CONNECT';

    # Basic proxy authentication
    my $userinfo = $proxy->userinfo;
    $headers->proxy_authorization('Basic ' . b64_encode($userinfo, ''))
      if $userinfo && !$headers->proxy_authorization;
  }

  # Host
  my $host = $url->ihost;
  my $port = $url->port;
  $headers->host($port ? "$host:$port" : $host) unless $headers->host;

  return $self;
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;

  # Request line
  unless (defined $self->{start_buffer}) {

    # Path
    my $url   = $self->url;
    my $path  = $url->path->to_string;
    my $query = $url->query->to_string;
    $path .= "?$query" if $query;
    $path = "/$path" unless $path =~ m!^/!;

    # CONNECT
    my $method = uc $self->method;
    if ($method eq 'CONNECT') {
      my $port = $url->port || ($url->scheme eq 'https' ? '443' : '80');
      $path = $url->host . ":$port";
    }

    # Proxy
    elsif ($self->proxy) {
      my $clone = $url = $url->clone->userinfo(undef);
      my $upgrade = lc($self->headers->upgrade || '');
      my $scheme = $url->scheme || '';
      $path = $clone unless $upgrade eq 'websocket' || $scheme eq 'https';
    }

    $self->{start_buffer} = "$method $path HTTP/@{[$self->version]}\x0d\x0a";
  }

  # Progress
  $self->emit(progress => 'start_line', $offset);

  # Chunk
  return substr $self->{start_buffer}, $offset, 131072;
}

sub is_secure {
  my $url = shift->url;
  return ($url->scheme || $url->base->scheme) ~~ 'https';
}

sub is_xhr {
  (shift->headers->header('X-Requested-With') || '') =~ /XMLHttpRequest/i;
}

sub param { shift->params->param(@_) }

sub params {
  my $self = shift;
  return $self->{params}
    ||= Mojo::Parameters->new->merge($self->body_params, $self->query_params);
}

sub parse {
  my $self = shift;
  my $env  = @_ > 1 ? {@_} : ref $_[0] eq 'HASH' ? $_[0] : undef;
  my @args = $env ? undef : @_;

  # CGI like environment
  $self->env($env)->_parse_env($env) if $env;
  $self->content($self->content->parse_body(@args)) if $self->{state} ~~ 'cgi';

  # Pass through
  $self->SUPER::parse(@args);

  # Check if we can fix things that require all headers
  return $self unless $self->is_finished;

  # Base URL
  my $base = $self->url->base;
  $base->scheme('http') unless $base->scheme;
  my $headers = $self->headers;
  if (!$base->host && (my $host = $headers->host)) { $base->authority($host) }

  # Basic authentication
  if (my $userinfo = _parse_basic_auth($headers->authorization)) {
    $base->userinfo($userinfo);
  }

  # Basic proxy authentication
  if (my $userinfo = _parse_basic_auth($headers->proxy_authorization)) {
    $self->proxy(Mojo::URL->new->userinfo($userinfo));
  }

  # "X-Forwarded-HTTPS"
  $base->scheme('https')
    if $ENV{MOJO_REVERSE_PROXY} && $headers->header('X-Forwarded-HTTPS');

  return $self;
}

# "Bart, with $10,000, we'd be millionaires!
#  We could buy all kinds of useful things like...love!"
sub proxy {
  my $self = shift;
  return $self->{proxy} unless @_;
  $self->{proxy} = !$_[0] || ref $_[0] ? shift : Mojo::URL->new(shift);
  return $self;
}

sub query_params { shift->url->query }

sub _parse_basic_auth {
  return unless my $header = shift;
  return $header =~ /Basic (.+)$/ ? b64_decode($1) : undef;
}

sub _parse_env {
  my ($self, $env) = @_;

  # Extract headers
  my $headers = $self->headers;
  my $url     = $self->url;
  my $base    = $url->base;
  while (my ($name, $value) = each %$env) {
    next unless $name =~ /^HTTP_/i;
    $name =~ s/^HTTP_//i;
    $name =~ s/_/-/g;
    $headers->header($name, $value);

    # Host/Port
    if ($name eq 'HOST') {
      my ($host, $port) = ($value, undef);
      ($host, $port) = ($1, $2) if $host =~ /^([^\:]*)\:?(.*)$/;
      $base->host($host)->port($port);
    }
  }

  # Content-Type is a special case on some servers
  $headers->content_type($env->{CONTENT_TYPE}) if $env->{CONTENT_TYPE};

  # Content-Length is a special case on some servers
  $headers->content_length($env->{CONTENT_LENGTH}) if $env->{CONTENT_LENGTH};

  # Query
  $url->query->parse($env->{QUERY_STRING}) if $env->{QUERY_STRING};

  # Method
  $self->method($env->{REQUEST_METHOD}) if $env->{REQUEST_METHOD};

  # Scheme/Version
  if (($env->{SERVER_PROTOCOL} || '') =~ m!^([^/]+)/([^/]+)$!) {
    $base->scheme($1);
    $self->version($2);
  }

  # HTTPS
  $base->scheme('https') if $env->{HTTPS};

  # Path
  my $path = $url->path->parse($env->{PATH_INFO} ? $env->{PATH_INFO} : '');

  # Base path
  if (my $value = $env->{SCRIPT_NAME}) {

    # Make sure there is a trailing slash (important for merging)
    $base->path->parse($value =~ m!/$! ? $value : "$value/");

    # Remove SCRIPT_NAME prefix if necessary
    my $buffer = $path->to_string;
    $value  =~ s!^/!!;
    $value  =~ s!/$!!;
    $buffer =~ s!^/?$value/?!!;
    $buffer =~ s!^/!!;
    $path->parse($buffer);
  }

  # Bypass normal content parser
  $self->{state} = 'cgi';
}

1;

=head1 NAME

Mojo::Message::Request - HTTP request

=head1 SYNOPSIS

  use Mojo::Message::Request;

  # Parse
  my $req = Mojo::Message::Request->new;
  $req->parse("GET /foo HTTP/1.0\x0a\x0d");
  $req->parse("Content-Length: 12\x0a\x0d\x0a\x0d");
  $req->parse("Content-Type: text/plain\x0a\x0d\x0a\x0d");
  $req->parse('Hello World!');
  say $req->method;
  say $req->headers->content_type;
  say $req->body;

  # Build
  my $req = Mojo::Message::Request->new;
  $req->url->parse('http://127.0.0.1/foo/bar');
  $req->method('GET');
  say $req->to_string;

=head1 DESCRIPTION

L<Mojo::Message::Request> is a container for HTTP requests as described in RFC
2616.

=head1 EVENTS

L<Mojo::Message::Request> inherits all events from L<Mojo::Message>.

=head1 ATTRIBUTES

L<Mojo::Message::Request> inherits all attributes from L<Mojo::Message> and
implements the following new ones.

=head2 C<env>

  my $env = $req->env;
  $req    = $req->env({});

Direct access to the C<CGI> or C<PSGI> environment hash if available.

  # Check CGI version
  my $version = $req->env->{GATEWAY_INTERFACE};

  # Check PSGI version
  my $version = $req->env->{'psgi.version'};

=head2 C<method>

  my $method = $req->method;
  $req       = $req->method('POST');

HTTP request method, defaults to C<GET>.

=head2 C<url>

  my $url = $req->url;
  $req    = $req->url(Mojo::URL->new);

HTTP request URL, defaults to a L<Mojo::URL> object.

  # Get request path
  say $req->url->path;

=head1 METHODS

L<Mojo::Message::Request> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 C<clone>

  my $clone = $req->clone;

Clone request if possible, otherwise return C<undef>.

=head2 C<cookies>

  my $cookies = $req->cookies;
  $req        = $req->cookies(Mojo::Cookie::Request->new);
  $req        = $req->cookies({name => 'foo', value => 'bar'});

Access request cookies, usually L<Mojo::Cookie::Request> objects.

=head2 C<extract_start_line>

  my $success = $req->extract_start_line(\$string);

Extract request line from string.

=head2 C<fix_headers>

  $req = $req->fix_headers;

Make sure request has all required headers for the current HTTP version.

=head2 C<get_start_line_chunk>

  my $string = $req->get_start_line_chunk($offset);

Get a chunk of request line data starting from a specific position.

=head2 C<is_secure>

  my $success = $req->is_secure;

Check if connection is secure.

=head2 C<is_xhr>

  my $success = $req->is_xhr;

Check C<X-Requested-With> header for C<XMLHttpRequest> value.

=head2 C<param>

  my @names = $req->param;
  my $foo   = $req->param('foo');
  my @foo   = $req->param('foo');

Access C<GET> and C<POST> parameters. Note that this method caches all data,
so it should not be called before the entire request body has been received.

=head2 C<params>

  my $p = $req->params;

All C<GET> and C<POST> parameters, usually a L<Mojo::Parameters> object. Note
that this method caches all data, so it should not be called before the entire
request body has been received.

  # Get parameter value
  say $req->params->param('foo');

=head2 C<parse>

  $req = $req->parse('GET /foo/bar HTTP/1.1');
  $req = $req->parse(REQUEST_METHOD => 'GET');
  $req = $req->parse({REQUEST_METHOD => 'GET'});

Parse HTTP request chunks or environment hash.

=head2 C<proxy>

  my $proxy = $req->proxy;
  $req      = $req->proxy('http://foo:bar@127.0.0.1:3000');
  $req      = $req->proxy(Mojo::URL->new('http://127.0.0.1:3000'));

Proxy URL for request.

  # Disable proxy
  $req->proxy(0);

=head2 C<query_params>

  my $p = $req->query_params;

All C<GET> parameters, usually a L<Mojo::Parameters> object.

  # Turn GET parameters to hash and extract value
  say $req->query_params->to_hash->{foo};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
