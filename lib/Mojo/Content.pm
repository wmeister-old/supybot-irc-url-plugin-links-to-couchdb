package Mojo::Content;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Headers;

has [qw(auto_relax relaxed)] => 0;
has headers => sub { Mojo::Headers->new };
has max_leftover_size => sub { $ENV{MOJO_MAX_LEFTOVER_SIZE} || 262144 };

sub body_contains {
  croak 'Method "body_contains" not implemented by subclass';
}

sub body_size { croak 'Method "body_size" not implemented by subclass' }

sub boundary {
  my $type = shift->headers->content_type || '';
  $type =~ m!multipart.*boundary="*([a-zA-Z0-9'(),.:?\-_+/]+)!i and return $1;
  return;
}

# "Operator! Give me the number for 911!"
sub build_body    { shift->_build('get_body_chunk') }
sub build_headers { shift->_build('get_header_chunk') }

sub charset {
  my $type = shift->headers->content_type || '';
  return $type =~ /charset="?([^"\s;]+)"?/i ? $1 : undef;
}

sub clone {
  my $self = shift;
  return if $self->is_dynamic;
  return $self->new(headers => $self->headers->clone);
}

sub generate_body_chunk {
  my ($self, $offset) = @_;

  # Drain
  $self->emit(drain => $offset)
    if !delete $self->{delay} && !length $self->{body_buffer};

  # Get chunk
  my $chunk = $self->{body_buffer} // '';
  $self->{body_buffer} = '';

  # EOF or delay
  return $self->{eof} ? '' : undef unless length $chunk;

  return $chunk;
}

sub get_body_chunk {
  croak 'Method "get_body_chunk" not implemented by subclass';
}

sub get_header_chunk {
  my ($self, $offset) = @_;

  unless (defined $self->{header_buffer}) {
    my $headers = $self->headers->to_string;
    $self->{header_buffer}
      = $headers ? "$headers\x0d\x0a\x0d\x0a" : "\x0d\x0a";
  }

  return substr $self->{header_buffer}, $offset, 131072;
}

sub has_leftovers { !!length(shift->{buffer} || '') }

sub header_size { length shift->build_headers }

sub is_chunked { (shift->headers->transfer_encoding || '') =~ /chunked/i }

sub is_dynamic {
  my $self = shift;
  return $self->{dynamic} && !defined $self->headers->content_length;
}

sub is_finished { shift->{state} ~~ 'finished' }

sub is_multipart {undef}

sub is_parsing_body { shift->{state} ~~ 'body' }

sub leftovers { shift->{buffer} }

sub parse {
  my $self = shift;

  # Parse headers
  $self->parse_until_body(@_);
  return $self if $self->{state} eq 'headers';
  $self->_body;

  # Relaxed parsing
  my $headers = $self->headers;
  if ($self->auto_relax) {
    my $connection = $headers->connection || '';
    my $len = $headers->content_length // '';
    $self->relaxed(1)
      if !length $len && ($connection =~ /close/i || $headers->content_type);
  }

  # Parse chunked content
  $self->{real_size} //= 0;
  if ($self->is_chunked && $self->{state} ne 'headers') {
    $self->_parse_chunked;
    $self->{state} = 'finished' if $self->{chunked_state} ~~ 'finished';
  }

  # Not chunked, pass through to second buffer
  else {
    $self->{real_size} += length $self->{pre_buffer};
    my $limit = $self->is_finished
      && length($self->{buffer}) > $self->max_leftover_size;
    $self->{buffer} .= $self->{pre_buffer} unless $limit;
    $self->{pre_buffer} = '';
  }

  # Chunked or relaxed content
  if ($self->is_chunked || $self->relaxed) {
    $self->{size} += length($self->{buffer} //= '');
    $self->emit(read => $self->{buffer})->{buffer} = '';
  }

  # Normal content
  else {
    my $len = $headers->content_length || 0;
    $self->{size} ||= 0;
    if ((my $need = $len - $self->{size}) > 0) {
      my $chunk = substr $self->{buffer}, 0, $need, '';
      $self->emit(read => $chunk)->{size} += length $chunk;
    }

    # Finished
    $self->{state} = 'finished' if $len <= $self->progress;
  }

  return $self;
}

sub parse_body {
  my $self = shift;
  $self->{state} = 'body';
  return $self->parse(@_);
}

sub parse_until_body {
  my ($self, $chunk) = @_;

  # Add chunk
  $self->{raw_size} += length($chunk //= '');
  $self->{pre_buffer} .= $chunk;

  # Parser started
  unless ($self->{state}) {

    # Update size
    $self->{header_size} = $self->{raw_size} - length $self->{pre_buffer};

    # Headers
    $self->{state} = 'headers';
  }

  # Parse headers
  $self->_parse_headers if $self->{state} ~~ 'headers';

  return $self;
}

sub progress {
  my $self = shift;
  return 0 unless $self->{state} ~~ [qw(body finished)];
  return $self->{raw_size} - ($self->{header_size} || 0);
}

sub write {
  my ($self, $chunk, $cb) = @_;

  # Dynamic content
  $self->{dynamic} = 1;

  # Add chunk
  if (defined $chunk) { $self->{body_buffer} .= $chunk }

  # Delay
  else { $self->{delay} = 1 }

  # Drain
  $self->once(drain => $cb) if $cb;

  # Finish
  $self->{eof} = 1 if defined $chunk && $chunk eq '';

  return $self;
}

# "Here's to alcohol, the cause of-and solution to-all life's problems."
sub write_chunk {
  my ($self, $chunk, $cb) = @_;

  # Chunked transfer encoding
  $self->headers->transfer_encoding('chunked') unless $self->is_chunked;

  # Write
  $self->write(defined $chunk ? $self->_build_chunk($chunk) : $chunk, $cb);

  # Finish
  $self->{eof} = 1 if defined $chunk && $chunk eq '';

  return $self;
}

sub _body {
  my $self = shift;
  $self->emit('body') unless $self->{body}++;
}

sub _build {
  my ($self, $method) = @_;

  # Build part from chunks
  my $buffer = '';
  my $offset = 0;
  while (1) {

    # No chunk yet, try again
    next unless defined(my $chunk = $self->$method($offset));

    # End of part
    last unless my $len = length $chunk;

    # Part
    $offset += $len;
    $buffer .= $chunk;
  }

  return $buffer;
}

sub _build_chunk {
  my ($self, $chunk) = @_;

  # End
  return "\x0d\x0a0\x0d\x0a\x0d\x0a" if length $chunk == 0;

  # First chunk has no leading CRLF
  my $crlf = $self->{chunks}++ ? "\x0d\x0a" : '';
  return $crlf . sprintf('%x', length $chunk) . "\x0d\x0a$chunk";
}

sub _parse_chunked {
  my $self = shift;

  # Trailing headers
  return $self->_parse_chunked_trailing_headers
    if $self->{chunked_state} ~~ 'trailing_headers';

  # New chunk (ignore the chunk extension)
  while ($self->{pre_buffer} =~ /^((?:\x0d?\x0a)?([\da-fA-F]+).*\x0d?\x0a)/) {
    my $header = $1;
    my $len    = hex $2;

    # Check if we have a whole chunk yet
    last unless length($self->{pre_buffer}) >= (length($header) + $len);

    # Remove header
    substr $self->{pre_buffer}, 0, length $header, '';

    # Last chunk
    if ($len == 0) {
      $self->{chunked_state} = 'trailing_headers';
      last;
    }

    # Remove payload
    $self->{real_size} += $len;
    $self->{buffer} .= substr $self->{pre_buffer}, 0, $len, '';

    # Remove newline at end of chunk
    $self->{pre_buffer} =~ s/^(\x0d?\x0a)//;
  }

  # Trailing headers
  $self->_parse_chunked_trailing_headers
    if $self->{chunked_state} ~~ 'trailing_headers';
}

sub _parse_chunked_trailing_headers {
  my $self = shift;

  # Parse
  my $headers = $self->headers->parse($self->{pre_buffer});
  $self->{pre_buffer} = '';

  # Check if we are finished
  return unless $headers->is_finished;
  $self->{chunked_state} = 'finished';

  # Replace Transfer-Encoding with Content-Length
  my $encoding = $headers->transfer_encoding;
  $encoding =~ s/,?\s*chunked//ig;
  $encoding
    ? $headers->transfer_encoding($encoding)
    : $headers->remove('Transfer-Encoding');
  $headers->content_length($self->{real_size});
}

sub _parse_headers {
  my $self = shift;

  # Parse
  my $headers = $self->headers->parse($self->{pre_buffer});
  $self->{pre_buffer} = '';

  # Check if we are finished
  return unless $headers->is_finished;
  $self->{state} = 'body';

  # Take care of leftovers
  my $leftovers = $self->{pre_buffer} = $headers->leftovers;
  $self->{header_size} = $self->{raw_size} - length $leftovers;
  $self->_body;
}

1;

=head1 NAME

Mojo::Content - HTTP content base class

=head1 SYNOPSIS

  package Mojo::Content::MyContent;
  use Mojo::Base 'Mojo::Content';

  sub body_contains  {...}
  sub body_size      {...}
  sub get_body_chunk {...}

=head1 DESCRIPTION

L<Mojo::Content> is an abstract base class for HTTP content as described in
RFC 2616.

=head1 EVENTS

L<Mojo::Content> can emit the following events.

=head2 C<body>

  $content->on(body => sub {
    my $content = shift;
    ...
  });

Emitted once all headers have been parsed and the body starts.

  $content->on(body => sub {
    my $content = shift;
    $content->auto_upgrade(0) if $content->headers->header('X-No-MultiPart');
  });

=head2 C<drain>

  $content->on(drain => sub {
    my ($content, $offset) = @_;
    ...
  });

Emitted once all data has been written.

  $content->on(drain => sub {
    my $content = shift;
    $content->write_chunk(time);
  });

=head2 C<read>

  $content->on(read => sub {
    my ($content, $chunk) = @_;
    ...
  });

Emitted when a new chunk of content arrives.

  $content->unsubscribe('read');
  $content->on(read => sub {
    my ($content, $chunk) = @_;
    say "Streaming: $chunk";
  });

=head1 ATTRIBUTES

L<Mojo::Content> implements the following attributes.

=head2 C<auto_relax>

  my $relax = $content->auto_relax;
  $content  = $content->auto_relax(1);

Try to detect broken web servers and turn on relaxed parsing automatically.

=head2 C<headers>

  my $headers = $content->headers;
  $content    = $content->headers(Mojo::Headers->new);

Content headers, defaults to a L<Mojo::Headers> object.

=head2 C<max_leftover_size>

  my $size = $content->max_leftover_size;
  $content = $content->max_leftover_size(1024);

Maximum size in bytes of buffer for pipelined HTTP requests, defaults to the
value of the C<MOJO_MAX_LEFTOVER_SIZE> environment variable or C<262144>.

=head2 C<relaxed>

  my $relaxed = $content->relaxed;
  $content    = $content->relaxed(1);

Activate relaxed parsing for responses that are terminated with a connection
close.

=head1 METHODS

L<Mojo::Content> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<body_contains>

  my $success = $content->body_contains('foo bar baz');

Check if content contains a specific string. Meant to be overloaded in a
subclass.

=head2 C<body_size>

  my $size = $content->body_size;

Content size in bytes. Meant to be overloaded in a subclass.

=head2 C<boundary>

  my $boundary = $content->boundary;

Extract multipart boundary from C<Content-Type> header.

=head2 C<build_body>

  my $string = $content->build_body;

Render whole body.

=head2 C<build_headers>

  my $string = $content->build_headers;

Render all headers.

=head2 C<charset>

  my $charset = $content->charset;

Extract charset from C<Content-Type> header.

=head2 C<clone>

  my $clone = $content->clone;

Clone content if possible, otherwise return C<undef>.

=head2 C<generate_body_chunk>

  my $chunk = $content->generate_body_chunk(0);

Generate dynamic content.

=head2 C<get_body_chunk>

  my $chunk = $content->get_body_chunk(0);

Get a chunk of content starting from a specfic position. Meant to be
overloaded in a subclass.

=head2 C<get_header_chunk>

  my $chunk = $content->get_header_chunk(13);

Get a chunk of the headers starting from a specfic position.

=head2 C<has_leftovers>

  my $success = $content->has_leftovers;

Check if there are leftovers.

=head2 C<header_size>

  my $size = $content->header_size;

Size of headers in bytes.

=head2 C<is_chunked>

  my $success = $content->is_chunked;

Check if content is chunked.

=head2 C<is_dynamic>

  my $success = $content->is_dynamic;

Check if content will be dynamically generated, which prevents C<clone> from
working.

=head2 C<is_finished>

  my $success = $content->is_finished;

Check if parser is finished.

=head2 C<is_multipart>

  my $false = $content->is_multipart;

False.

=head2 C<is_parsing_body>

  my $success = $content->is_parsing_body;

Check if body parsing started yet.

=head2 C<leftovers>

  my $bytes = $content->leftovers;

Get leftover data from content parser.

=head2 C<parse>

  $content = $content->parse("Content-Length: 12\r\n\r\nHello World!");

Parse content chunk.

=head2 C<parse_body>

  $content = $content->parse_body('Hi!');

Parse body chunk.

=head2 C<parse_until_body>

  $content
    = $content->parse_until_body("Content-Length: 12\r\n\r\nHello World!");

Parse chunk and stop after headers.

=head2 C<progress>

  my $size = $content->progress;

Size of content already received from message in bytes.

=head2 C<write>

  $content = $content->write('Hello!');
  $content = $content->write('Hello!', sub {...});

Write dynamic content non-blocking, the optional drain callback will be
invoked once all data has been written.

=head2 C<write_chunk>

  $content = $content->write_chunk('Hello!');
  $content = $content->write_chunk('Hello!', sub {...});

Write dynamic content non-blocking with C<chunked> transfer encoding, the
optional drain callback will be invoked once all data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
