package Mojolicious::Lite;
use Mojo::Base 'Mojolicious';

# "Since when is the Internet all about robbing people of their privacy?
#  August 6, 1991."
use File::Basename 'dirname';
use File::Spec::Functions 'catdir';
use Mojo::UserAgent;

# "It's the future, my parents, my co-workers, my girlfriend,
#  I'll never see any of them ever again... YAHOOO!"
sub import {
  my $class = shift;

  # Executable
  $ENV{MOJO_EXE} ||= (caller)[1];

  # Home
  local $ENV{MOJO_HOME} = catdir(split '/', dirname($ENV{MOJO_EXE}))
    unless $ENV{MOJO_HOME};

  # Initialize app
  no strict 'refs';
  my $caller = caller;
  push @{"${caller}::ISA"}, 'Mojo';
  my $app = $class->new;

  # Initialize routes
  my $routes = $app->routes->namespace('');

  # Default static and template class
  $app->static->classes->[0] = $app->renderer->classes->[0] = $caller;

  # Export
  no warnings 'redefine';
  my $root = $routes;
  for my $name (qw(any get options patch post put websocket)) {
    *{"${caller}::$name"} = sub { $routes->$name(@_) };
  }
  *{"${caller}::new"} = *{"${caller}::app"} = sub {$app};
  *{"${caller}::del"} = sub { $routes->delete(@_) };
  *{"${caller}::group"} = sub (&) {
    my $old = $root;
    $_[0]->($root = $routes);
    ($routes, $root) = ($root, $old);
  };
  *{"${caller}::helper"} = sub { $app->helper(@_) };
  *{"${caller}::hook"}   = sub { $app->hook(@_) };
  *{"${caller}::plugin"} = sub { $app->plugin(@_) };
  *{"${caller}::under"}  = sub { $routes = $root->under(@_) };

  # Make sure there's a default application for testing
  Mojo::UserAgent->app($app) unless Mojo::UserAgent->app;

  # Lite apps are strict!
  Mojo::Base->import(-strict);
}

1;

=head1 NAME

Mojolicious::Lite - Real-time micro web framework

=head1 SYNOPSIS

  # Automatically enables "strict", "warnings" and Perl 5.10 features
  use Mojolicious::Lite;

  # Route with placeholder
  get '/:foo' => sub {
    my $self = shift;
    my $foo  = $self->param('foo');
    $self->render(text => "Hello from $foo.");
  };

  # Start the Mojolicious command system
  app->start;

=head1 DESCRIPTION

L<Mojolicious::Lite> is a micro real-time web framework built around
L<Mojolicious>.

=head1 TUTORIAL

A quick example driven introduction to the wonders of L<Mojolicious::Lite>.
Most of what you'll learn here also applies to normal L<Mojolicious>
applications.

=head2 Hello World

A simple Hello World application can look like this, L<strict>, L<warnings>
and Perl 5.10 features are automatically enabled and a few functions imported
when you use L<Mojolicious::Lite>, turning your script into a full featured
web application.

  #!/usr/bin/env perl
  use Mojolicious::Lite;

  get '/' => sub {
    my $self = shift;
    $self->render(text => 'Hello World!');
  };

  app->start;

=head2 Generator

There is also a helper command to generate a small example application.

  $ mojo generate lite_app

=head2 Commands

All the normal L<Mojolicious::Commands> are available from the command line.
Note that CGI and L<PSGI> environments can usually be auto detected and will
just work without commands.

  $ ./myapp.pl daemon
  Server available at http://127.0.0.1:3000.

  $ ./myapp.pl daemon -l http://*:8080
  Server available at http://127.0.0.1:8080.

  $ ./myapp.pl cgi
  ...CGI output...

  $ ./myapp.pl
  ...List of available commands (or automatically detected environment)...

=head2 Start

The app->start call that starts the L<Mojolicious> command system can be
customized to override normal C<@ARGV> use.

  app->start('cgi');

=head2 Reloading

Your application will automatically reload itself if you start it with the
C<morbo> development web server, so you don't have to restart the server after
every change.

  $ morbo myapp.pl
  Server available at http://127.0.0.1:3000.

=head2 Routes

Routes are basically just fancy paths that can contain different kinds of
placeholders. C<$self> is a L<Mojolicious::Controller> object containing both,
the HTTP request and response.

  use Mojolicious::Lite;

  # /foo
  get '/foo' => sub {
    my $self = shift;
    $self->render(text => 'Hello World!');
  };

  app->start;

=head2 GET/POST parameters

All C<GET> and C<POST> parameters are accessible via
L<Mojolicious::Controller/"param">.

  use Mojolicious::Lite;

  # /foo?user=sri
  get '/foo' => sub {
    my $self = shift;
    my $user = $self->param('user');
    $self->render(text => "Hello $user.");
  };

  app->start;

=head2 Stash and templates

The L<Mojolicious::Controller/"stash"> is used to pass data to templates,
which can be inlined in the C<DATA> section.

  use Mojolicious::Lite;

  # /bar
  get '/bar' => sub {
    my $self = shift;
    $self->stash(one => 23);
    $self->render('baz', two => 24);
  };

  app->start;
  __DATA__

  @@ baz.html.ep
  The magic numbers are <%= $one %> and <%= $two %>.

For more information about templates see also
L<Mojolicious::Guides::Rendering/"Embedded Perl">.

=head2 HTTP

L<Mojolicious::Controller/"req"> and L<Mojolicious::Controller/"res"> give you
full access to all HTTP features and information.

  use Mojolicious::Lite;

  # /agent
  get '/agent' => sub {
    my $self = shift;
    $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
    $self->render(text => $self->req->headers->user_agent);
  };

  app->start;

=head2 Route names

All routes can have a name associated with them, this allows automatic
template detection and back referencing with
L<Mojolicious::Controller/"url_for"> as well as many helpers like
L<Mojolicious::Plugin::TagHelpers/"link_to">. Nameless routes get an
automatically generated one assigned that is simply equal to the route itself
without non-word characters.

  use Mojolicious::Lite;

  # /
  get '/' => sub {
    my $self = shift;
    $self->render;
  } => 'index';

  # /hello
  get '/hello';

  app->start;
  __DATA__

  @@ index.html.ep
  <%= link_to Hello  => 'hello' %>.
  <%= link_to Reload => 'index' %>.

  @@ hello.html.ep
  Hello World!

=head2 Layouts

Templates can have layouts too, you just select one with the helper
L<Mojolicious::Plugin::DefaultHelpers/"layout"> and place the result of the
current template with the helper
L<Mojolicious::Plugin::DefaultHelpers/"content">.

  use Mojolicious::Lite;

  # /with_layout
  get '/with_layout' => sub {
    my $self = shift;
    $self->render('with_layout');
  };

  app->start;
  __DATA__

  @@ with_layout.html.ep
  % title 'Green';
  % layout 'green';
  Hello World!

  @@ layouts/green.html.ep
  <!DOCTYPE html>
  <html>
    <head><title><%= title %></title></head>
    <body><%= content %></body>
  </html>

=head2 Blocks

Template blocks can be used like normal Perl functions and are always
delimited by the C<begin> and C<end> keywords.

  use Mojolicious::Lite;

  # /with_block
  get '/with_block' => 'block';

  app->start;
  __DATA__

  @@ block.html.ep
  % my $link = begin
    % my ($url, $name) = @_;
    Try <%= link_to $url => begin %><%= $name %><% end %>.
  % end
  <!DOCTYPE html>
  <html>
    <head><title>Sebastians frameworks</title></head>
    <body>
      %= $link->('http://mojolicio.us', 'Mojolicious')
      %= $link->('http://catalystframework.org', 'Catalyst')
    </body>
  </html>

=head2 Captured content

The helper L<Mojolicious::Plugin::TagHelpers/"content_for"> can be used to
pass around blocks of captured content.

  use Mojolicious::Lite;

  # /captured
  get '/captured' => sub {
    my $self = shift;
    $self->render('captured');
  };

  app->start;
  __DATA__

  @@ captured.html.ep
  % layout 'blue', title => 'Green';
  % content_for header => begin
    <meta http-equiv="Pragma" content="no-cache">
  % end
  Hello World!
  % content_for header => begin
    <meta http-equiv="Expires" content="-1">
  % end

  @@ layouts/blue.html.ep
  <!DOCTYPE html>
  <html>
    <head>
      <title><%= title %></title>
      %= content_for 'header'
    </head>
    <body><%= content %></body>
  </html>

=head2 Helpers

You can also extend L<Mojolicious> with your own helpers, a list of all
built-in ones can be found in L<Mojolicious::Plugin::DefaultHelpers> and
L<Mojolicious::Plugin::TagHelpers>.

  use Mojolicious::Lite;

  # "whois" helper
  helper whois => sub {
    my $self  = shift;
    my $agent = $self->req->headers->user_agent || 'Anonymous';
    my $ip    = $self->tx->remote_address;
    return "$agent ($ip)";
  };

  # /secret
  get '/secret' => sub {
    my $self = shift;
    my $user = $self->whois;
    $self->app->log->debug("Request from $user.");
  };

  app->start;
  __DATA__

  @@ secret.html.ep
  We know who you are <%= whois %>.

=head2 Placeholders

Route placeholders allow capturing parts of a request path until a C</> or
C<.> separator occurs, results are accessible via
L<Mojolicious::Controller/"stash"> and L<Mojolicious::Controller/"param">.

  use Mojolicious::Lite;

  # /foo/test
  # /foo/test123
  get '/foo/:bar' => sub {
    my $self = shift;
    my $bar  = $self->stash('bar');
    $self->render(text => "Our :bar placeholder matched $bar");
  };

  # /testsomething/foo
  # /test123something/foo
  get '/(:bar)something/foo' => sub {
    my $self = shift;
    my $bar  = $self->param('bar');
    $self->render(text => "Our :bar placeholder matched $bar");
  };

  app->start;

=head2 Relaxed Placeholders

Relaxed placeholders allow matching of everything until a C</> occurs.

  use Mojolicious::Lite;

  # /test/hello
  # /test123/hello
  # /test.123/hello
  get '/#you/hello' => 'groovy';

  app->start;
  __DATA__

  @@ groovy.html.ep
  Your name is <%= $you %>.

=head2 Wildcard placeholders

Wildcard placeholders allow matching absolutely everything, including C</> and
C<.>.

  use Mojolicious::Lite;

  # /hello/test
  # /hello/test123
  # /hello/test.123/test/123
  get '/hello/*you' => 'groovy';

  app->start;
  __DATA__

  @@ groovy.html.ep
  Your name is <%= $you %>.

=head2 HTTP methods

Routes can be restricted to specific request methods.

  use Mojolicious::Lite;

  # GET /hello
  get '/hello' => sub {
    my $self = shift;
    $self->render(text => 'Hello World!');
  };

  # PUT /hello
  put '/hello' => sub {
    my $self = shift;
    my $size = length $self->req->body;
    $self->render(text => "You uploaded $size bytes to /hello.");
  };

  # GET|POST|PATCH /bye
  any [qw(GET POST PATCH)] => '/bye' => sub {
    my $self = shift;
    $self->render(text => 'Bye World!');
  };

  # * /whatever
  any '/whatever' => sub {
    my $self   = shift;
    my $method = $self->req->method;
    $self->render(text => "You called /whatever with $method.");
  };

  app->start;

=head2 Optional placeholders

Routes allow default values to make placeholders optional.

  use Mojolicious::Lite;

  # /hello
  # /hello/Sara
  get '/hello/:name' => {name => 'Sebastian'} => sub {
    my $self = shift;
    $self->render('groovy', format => 'txt');
  };

  app->start;
  __DATA__

  @@ groovy.txt.ep
  My name is <%= $name %>.

=head2 Restrictive placeholders

The easiest way to make placeholders more restrictive are alternatives, you
just make a list of possible values.

  use Mojolicious::Lite;

  # /test
  # /123
  any '/:foo' => [foo => [qw(test 123)]] => sub {
    my $self = shift;
    my $foo  = $self->param('foo');
    $self->render(text => "Our :foo placeholder matched $foo");
  };

  app->start;

All placeholders get compiled to a regular expression internally, this process
can also be easily customized.

  use Mojolicious::Lite;

  # /1
  # /123
  any '/:bar' => [bar => qr/\d+/] => sub {
    my $self = shift;
    my $bar  = $self->param('bar');
    $self->render(text => "Our :bar placeholder matched $bar");
  };

  app->start;

Just make sure not to use C<^> and C<$> or capturing groups C<(...)>, because
placeholders become part of a larger regular expression internally, C<(?:...)>
is fine though.

=head2 Under

Authentication and code shared between multiple routes can be realized easily
with bridge routes generated by the C<under> statement. All following routes
are only evaluated if the callback returned a true value.

  use Mojolicious::Lite;

  # Authenticate based on name parameter
  under sub {
    my $self = shift;

    # Authenticated
    my $name = $self->param('name') || '';
    return 1 if $name eq 'Bender';

    # Not authenticated
    $self->render('denied');
    return;
  };

  # / (with authentication)
  get '/' => 'index';

  app->start;
  __DATA__;

  @@ denied.html.ep
  You are not Bender, permission denied.

  @@ index.html.ep
  Hi Bender.

Prefixing multiple routes is another good use for C<under>.

  use Mojolicious::Lite;

  # /foo
  under '/foo';

  # /foo/bar
  get '/bar' => {text => 'foo bar'};

  # /foo/baz
  get '/baz' => {text => 'foo baz'};

  # /
  under '/' => {message => 'whatever'};

  # /bar
  get '/bar' => {inline => '<%= $message %> works'};

  app->start;

You can also C<group> related routes, which allows nesting of multiple
C<under> statements.

  use Mojolicious::Lite;

  # Global logic shared by all routes
  under sub {
    my $self = shift;
    return 1 if $self->req->headers->header('X-Bender');
    $self->render(text => "You're not Bender.");
    return;
  };

  # Admin section
  group {

    # Local logic shared only by routes in this group
    under '/admin' => sub {
      my $self = shift;
      return 1 if $self->req->heaers->header('X-Awesome');
      $self->render(text => "You're not awesome enough.");
      return;
    };

    # GET /admin/dashboard
    get '/dashboard' => {text => 'Nothing to see here yet.'};
  };

  # GET /welcome
  get '/welcome' => {text => 'Hi Bender.'};

  app->start;

=head2 Formats

Formats can be automatically detected by looking at file extensions.

  use Mojolicious::Lite;

  # /detection.html
  # /detection.txt
  get '/detection' => sub {
    my $self = shift;
    $self->render('detected');
  };


  app->start;
  __DATA__

  @@ detected.html.ep
  <!DOCTYPE html>
  <html>
    <head><title>Detected</title></head>
    <body>HTML was detected.</body>
  </html>

  @@ detected.txt.ep
  TXT was detected.

Restrictive placeholders can also be used.

  use Mojolicious::Lite;

  # /hello.json
  # /hello.txt
  get '/hello' => [format => [qw(json txt)]] => sub {
    my $self = shift;
    return $self->render_json({hello => 'world'})
      if $self->stash('format') eq 'json';
    $self->render_text('hello world');
  };

  app->start;

Or you can just disable format detection.

  use Mojolicious::Lite;

  # /hello
  get '/hello' => [format => 0] => {text => 'No format detection.'};

  # Disable detection and allow the following routes selective re-enabling
  under [format => 0];

  # /foo
  get '/foo' => {text => 'No format detection again.'};

  # /bar.txt
  get '/bar' => [format => 'txt'] => {text => ' Just one format.'};

  app->start;

=head2 Content negotiation

For resources with different representations and that require truly C<RESTful>
content negotiation you can also use L<Mojolicious::Controller/"respond_to">.

  use Mojolicious::Lite;

  # /hello (Accept: application/json)
  # /hello (Accept: text/xml)
  # /hello.json
  # /hello.xml
  # /hello?format=json
  # /hello?format=xml
  get '/hello' => sub {
    my $self = shift;
    $self->respond_to(
      json => {json => {hello => 'world'}},
      xml  => {text => '<hello>world</hello>'},
      any  => {data => '', status => 204}
    );
  };

  app->start;

MIME type mappings can be extended or changed easily with
L<Mojolicious/"types">.

  app->types->type(rdf => 'application/rdf+xml');

=head2 Conditions

Conditions such as C<agent> and C<host> from
L<Mojolicious::Plugin::HeaderCondition> allow even more powerful route
constructs.

  use Mojolicious::Lite;

  # /foo (Firefox)
  get '/foo' => (agent => qr/Firefox/) => sub {
    my $self = shift;
    $self->render(text => 'Congratulations, you are using a cool browser.');
  };

  # /foo (Internet Explorer)
  get '/foo' => (agent => qr/Internet Explorer/) => sub {
    my $self = shift;
    $self->render(text => 'Dude, you really need to upgrade to Firefox.');
  };

  # http://mojolicio.us/bar
  get '/bar' => (host => 'mojolicio.us') => sub {
    my $self = shift;
    $self->render(text => 'Hello Mojolicious.');
  };

  app->start;

=head2 Sessions

Signed cookie based sessions just work out of the box as soon as you start
using them through the helper
L<Mojolicious::Plugin::DefaultHelpers/"session">.

  use Mojolicious::Lite;

  get '/counter' => sub {
    my $self = shift;
    $self->session->{counter}++;
  };

  app->start;
  __DATA__

  @@ counter.html.ep
  Counter: <%= session 'counter' %>

Just be aware that all session data gets serialized with L<Mojo::JSON>.

=head2 Secret

Note that you should use a custom L<Mojolicious/"secret"> to make signed
cookies really secure.

  app->secret('My secret passphrase here');

=head2 File uploads

All files uploaded via C<multipart/form-data> request are automatically
available as L<Mojo::Upload> objects. And you don't have to worry about memory
usage, because all files above C<250KB> will be automatically streamed into a
temporary file.

  use Mojolicious::Lite;

  # Upload form in DATA section
  get '/' => 'form';

  # Multipart upload handler
  post '/upload' => sub {
    my $self = shift;

    # Check file size
    return $self->render(text => 'File is too big.', status => 200)
      if $self->req->is_limit_exceeded;

    # Process uploaded file
    return $self->redirect_to('form')
      unless my $example = $self->param('example');
    my $size = $example->size;
    my $name = $example->filename;
    $self->render(text => "Thanks for uploading $size byte file $name.");
  };

  app->start;
  __DATA__

  @@ form.html.ep
  <!DOCTYPE html>
  <html>
    <head><title>Upload</title></head>
    <body>
      %= form_for upload => (enctype => 'multipart/form-data') => begin
        %= file_field 'example'
        %= submit_button 'Upload'
      % end
    </body>
  </html>

To protect you from excessively large files there is also a limit of C<5MB> by
default, which you can tweak with the C<MOJO_MAX_MESSAGE_SIZE> environment
variable.

  # Increase limit to 1GB
  $ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

=head2 User agent

With L<Mojolicious::Controller/"ua"> there's a full featured HTTP and
WebSocket user agent built right in. Especially in combination with
L<Mojo::JSON> and L<Mojo::DOM> this can be a very powerful tool.

  use Mojolicious::Lite;

  get '/test' => sub {
    my $self = shift;
    $self->render(data => $self->ua->get('http://mojolicio.us')->res->body);
  };

  app->start;

=head2 WebSockets

WebSocket applications have never been this easy before.

  use Mojolicious::Lite;

  websocket '/echo' => sub {
    my $self = shift;
    $self->on(message => sub {
      my ($self, $message) = @_;
      $self->send("echo: $message");
    });
  };

  app->start;

The event L<Mojo::Transaction::WebSocket/"message">, which you can subscribe
to with L<Mojolicious::Controller/"on">, will be emitted for every new
WebSocket message that is received.

=head2 External templates

External templates will be searched by the renderer in a C<templates>
directory.

  use Mojolicious::Lite;

  # /external
  any '/external' => sub {
    my $self = shift;

    # templates/foo/bar.html.ep
    $self->render('foo/bar');
  };

  app->start;

=head2 Static files

Static files will be automatically served from the C<DATA> section (even
Base64 encoded) or a C<public> directory if it exists.

  @@ something.js
  alert('hello!');

  @@ test.txt (base64)
  dGVzdCAxMjMKbGFsYWxh

  $ mkdir public
  $ mv something.js public/something.js

=head2 Testing

Testing your application is as easy as creating a C<t> directory and filling
it with normal Perl unit tests.

  use Test::More tests => 3;
  use Test::Mojo;

  use FindBin;
  require "$FindBin::Bin/../myapp.pl";

  my $t = Test::Mojo->new;
  $t->get_ok('/')->status_is(200)->content_like(qr/Funky/);

Run all unit tests with the C<test> command.

  $ ./myapp.pl test

To make your tests more noisy and show you all log messages you can also
change the application log level directly in your test files.

  $t->app->log->level('debug');

=head2 Mode

To disable debug messages later in a production setup, you can change the
L<Mojolicious> operating mode with command line options or the C<MOJO_MODE>
environment variable, the default will usually be C<development>.

  $ ./myapp.pl daemon -m production

This also affects many other aspects of the framework, such as mode specific
C<exception> and C<not_found> templates.

=head2 Logging

L<Mojo::Log> messages will be automatically written to C<STDERR> or a
C<log/$mode.log> file if a C<log> directory exists.

  $ mkdir log

For more control the L<Mojolicious> object can be accessed directly.

  use Mojolicious::Lite;

  app->log->level('error');
  app->routes->get('/foo/:bar' => sub {
    my $self = shift;
    $self->app->log->debug('Got a request for "Hello Mojo!".');
    $self->render(text => 'Hello Mojo!');
  });

  app->start;

=head2 More

You can continue with L<Mojolicious::Guides> now, and don't forget to have
fun!

=head1 FUNCTIONS

L<Mojolicious::Lite> implements the following functions.

=head2 C<any>

  my $route = any '/:foo' => sub {...};
  my $route = any [qw(GET POST)] => '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"any">, matching any of the
listed HTTP request methods or all. See also the tutorial above for more
argument variations.

=head2 C<app>

  my $app = app;

The L<Mojolicious::Lite> application.

=head2 C<del>

  my $route = del '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"delete">, matching only
C<DELETE> requests. See also the tutorial above for more argument variations.

=head2 C<get>

  my $route = get '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"get">, matching only C<GET>
requests. See also the tutorial above for more argument variations.

=head2 C<group>

  group {...};

Start a new route group.

=head2 C<helper>

  helper foo => sub {...};

Add a new helper with L<Mojolicious/"helper">.

=head2 C<hook>

  hook after_dispatch => sub {...};

Share code with L<Mojolicious/"hook">.

=head2 C<options>

  my $route = options '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"options">, matching only
C<OPTIONS> requests. See also the tutorial above for more argument
variations.

=head2 C<patch>

  my $route = patch '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"patch">, matching only
C<PATCH> requests. See also the tutorial above for more argument variations.

=head2 C<plugin>

  plugin SomePlugin => {foo => 23};

Load a plugin with L<Mojolicious/"plugin">.

=head2 C<post>

  my $route = post '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"post">, matching only
C<POST> requests. See also the tutorial above for more argument variations.

=head2 C<put>

  my $route = put '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"put">, matching only C<PUT>
requests. See also the tutorial above for more argument variations.

=head2 C<under>

  my $route = under sub {...};
  my $route = under '/:foo';

Generate bridge route with L<Mojolicious::Routes::Route/"under">, to which all
following routes are automatically appended. See also the tutorial above for
more argument variations.

=head2 C<websocket>

  my $route = websocket '/:foo' => sub {...};

Generate route with L<Mojolicious::Routes::Route/"websocket">, matching only
C<WebSocket> handshakes. See also the tutorial above for more argument
variations.

=head1 ATTRIBUTES

L<Mojolicious::Lite> inherits all attributes from L<Mojolicious>.

=head1 METHODS

L<Mojolicious::Lite> inherits all methods from L<Mojolicious>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
