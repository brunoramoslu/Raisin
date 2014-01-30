package Raisin;

use strict;
use warnings;
use feature ':5.12';

use Carp;
use DDP; # XXX
#use Plack::Builder;
use Plack::Util;

use Raisin::Request;
use Raisin::Response;
use Raisin::Routes;

our $VERSION = '0.1';
our $CODENAME = 'Cabernet Sauvignon';

sub new {
    my ($class, %args) = @_;
    my $self = bless { %args }, $class;

    $self->{routes} = Raisin::Routes->new;
    $self->{mounted} = [];
    $self->{middleware} = {};

    $self;
}

sub load_plugin {
    my ($self, $name, @args) = @_;
    return if $self->{loaded_plugins}{$name};

    my $class = Plack::Util::load_class($name, 'Raisin::Plugin');
    my $module = $self->{loaded_plugins}{$name} = $class->new($self);

    $module->build(@args);
}

sub add_middleware {
    my ($self, $name, @args) = @_;
    $self->{middleware}{$name} = \@args;
}

# Routes
sub routes { shift->{routes} }
sub add_route { shift->routes->add(@_) }

# Hooks
sub hook {
    my ($self, $name) = @_;
    $self->{hooks}{$name} || sub {};
}

sub add_hook {
    my ($self, $name, $code) = @_;
    $self->{hooks}{$name} = $code;
}

# Application
sub mount_package {
    my ($self, $package) = @_;
    push @{ $self->{mounted} }, $package;
    $package = Plack::Util::load_class($package);
}

sub run {
    my $self = shift;
    my $app = sub { $self->psgi(@_) };

    # Add middleware
    for my $class (keys %{ $self->{middleware} }) {
        # Make sure the middleware was not already loaded
        next if $self->{_loaded_middleware}->{$class}++;

        my $mw = Plack::Util::load_class($class, 'Plack::Middleware');
        my $args = $self->{middleware}{$class};
        $app = $mw->wrap($app, @$args);
    }

    return $app;
}

sub psgi {
    my ($self, $env) = @_;

    # Diffrent for each response
    my $req = $self->req(Raisin::Request->new($env));
    my $res = $self->res(Raisin::Response->new($self));

    # TODO Check incoming content type
#    if (my $content_type = $self->default_content_type) {
#        if (!$req->content_type or $req->content_type ne $content_type) {
#            $res->render_error(409, 'Invalid format!');
#            return $self->res->finalize;
#        }
#    }

    # HOOK Before
    $self->hook('before')->($self);

    # Find route
    my $routes = $self->routes->find($req->method, $req->path);

    if (!@$routes) {
        $res->render_404;
        return $res->finalize;
    }

    eval {
        foreach my $route (@$routes) {
            my $code = $route->code; # endpoint

            if (!$code || (ref($code) && ref($code) ne 'CODE')) {
                die 'Invalid endpoint for ' . $req->path;
            }

            # Log
            if ($self->can('logger')) {
                $self->logger(info => $req->method . ' ' . $route->path);
            }

            # HOOK Before validation
            $self->hook('before_validation')->($self);

            # Load params
            my $params = $req->parameters->mixed;
            my $named = $route->named;
#say '-' . ' PARAMS -' x 3;
#p $params;
#p $named;
#say '*' . ' <--' x 3;

            # Validation # TODO BROKEN
            $req->set_declared_params($route->params);
            $req->set_named_params($route->named);

            # What TODO if parameters is invalid?
            if (not $req->validate_params) {
                warn '* ' . 'INVALID PARAMS! ' x 5;
                $res->render_error(400, 'Invalid params!');
                last;
            }

            my $declared_params = $req->declared_params;
#say '-' . ' DECLARED PARAMS -' x 3;
#p %declared_params;
#say '*' . ' <--' x 3;

            # HOOK After validation
            $self->hook('after_validation')->($self);

            # Eval code
            my $data = $code->($declared_params);

            # Format plugins
            if (ref $data && $self->can('serialize')) {
                $data = $self->serialize($data);
            }

            # Set default content type
            $res->content_type($self->default_content_type);

            if (defined $data) {
                # Handle delayed response
                return $data if ref($data) eq 'CODE'; # TODO check delayed responses
                $res->render($data) if not $res->rendered;
            }

            # HOOK After
            $self->hook('after')->($self);
        }

        if (!$res->rendered) {
            croak 'Nothing rendered!';
        }
    };

    if (my $e = $@) {
        #$e = longmess($e);
        $res->render_500($e);
    }

    $self->finalize;
}

# Finalize response
sub before_finalize {
    my $self = shift;
    $self->res->header('X-Framework' => "Raisin $VERSION");
}

sub finalize {
    my $self = shift;
    $self->before_finalize;
    $self->res->finalize;
}

# Application defaults
sub api_format {
    my ($self, $name) = @_;
    $name = $name =~ /\+/ ? $name : "Format::$name";
    $self->load_plugin($name);
}

sub default_content_type { shift->{default_content_type} || 'text/plain' }

# Request and Response and shortcuts
sub req {
    my ($self, $req) = @_;
    $self->{req} = $req if $req;
    $self->{req};
}

sub res {
    my ($self, $res) = @_;
    $self->{res} = $res if $res;
    $self->{res};
}

sub params { shift->req->parameters->mixed }

sub session {
    my $self = shift;

    if (not $self->req->env->{'psgix.session'}) {
        croak "No Session middleware wrapped";
    }

    $self->req->session;
}

1;

=head1 NAME

Raisin - A REST-like API micro-framework for Perl.

=head1 SYNOPSYS

    use Raisin::DSL;

    my %USERS = (
        1 => {
            name => 'Darth Wader',
            password => 'death',
            email => 'darth@deathstar.com',
        },
        2 => {
            name => 'Luke Skywalker',
            password => 'qwerty',
            email => 'l.skywalker@jedi.com',
        },
    );

    namespace '/user' => sub {
        get params => [
            #required/optional => [name, type, default, regex]
            optional => ['start', $Raisin::Types::Integer, 0],
            optional => ['count', $Raisin::Types::Integer, 10],
        ],
        sub {
            my $params = shift;
            my ($start, $count) = ($params->{start}, $params->{count});

            my @users
                = map { { id => $_, %{ $USERS{$_} } } }
                  sort { $a <=> $b } keys %USERS;

            $start = $start > scalar @users ? scalar @users : $start;
            $count = $count > scalar @users ? scalar @users : $count;

            my @slice = @users[$start .. $count];
            { data => \@slice }
        };

        post params => [
            required => ['name', $Raisin::Types::String],
            required => ['password', $Raisin::Types::String],
            optional => ['email', $Raisin::Types::String, undef, qr/.+\@.+/],
        ],
        sub {
            my $params = shift;

            my $id = max(keys %USERS) + 1;
            $USERS{$id} = $params;

            { success => 1 }
        };

        route_param 'id' => $Raisin::Types::Integer,
        sub {
            get sub {
                my $params = shift;
                %USERS{ $params->{id} };
            };
        };
    };

    run;

=head1 DESCRIPTION

Raisin is a REST-like API micro-framework for Perl.
It's designed to run on Plack, providing a simple DSL to easily develop RESTful APIs.
It was inspired by L<Grape|https://github.com/intridea/grape>.

=head1 KEYWORDS

=head3 namespace

    namespace user => sub { ... };

=head3 route_param

    route_param id => $Raisin::Types::Integer, sub { ... };

=head3 delete, get, post, put

These are shortcuts to C<route> restricted to the corresponding HTTP method.

    get sub { 'GET' };

    get params => [
        required => ['id', $Raisin::Types::Integer],
        optional => ['key', $Raisin::Types::String],
    ],
    sub { 'GET' };

=head3 req

An alias for C<$self-E<gt>req>, this provides quick access to the
L<Raisin::Request> object for the current route.

=head3 res

An alias for C<$self-E<gt>res>, this provides quick access to the
L<Raisin::Response> object for the current route.

=head3 params

An alias for C<$self-E<gt>params> that gets the GET and POST parameters.
When used with no arguments, it will return an array with the names of all http
parameters. Otherwise, it will return the value of the requested http parameter.

Returns L<Hash::MultiValue> object.

=head3 session

An alias for C<$self-E<gt>session> that returns (optional) psgix.session hash.
When it exists, you can retrieve and store per-session data from and to this hash.

=head3 api_format

Load a C<Raisin::Plugin::Format> plugin.

Already exists L<Raisin::Plugin::Format::JSON> and L<Raisin::Plugin::Format::YAML>.

    api_format 'JSON';

=head3 plugin

Loads a Raisin module. The module options may be specified after the module name.
Compatible with L<Kelp> modules.

    plugin 'Logger' => outputs => [['Screen', min_level => 'debug']];

=head3 middleware

Loads middleware to your application.

    middleware '+Plack::Middleware::Session' => { store => 'File' };
    middleware '+Plack::Middleware::ContentLength';
    middleware 'Runtime'; # will be loaded Plack::Middleware::Runtime

=head3 mount

Mount multiple API implementations inside another one.  These don't have to be
different versions, but may be components of the same API.

In C<RaisinApp.pm>:

    package RaisinApp;

    use Raisin::DSL;

    api_format 'JSON';

    mount 'RaisinApp::User';
    mount 'RaisinApp::Host';

    1;

=head3 run, new

Creates and returns a PSGI ready subroutine, and makes the app ready for C<Plack>.

=head2 Parameters

Request parameters are available through the params hash object. This includes
GET, POST and PUT parameters, along with any named parameters you specify in
your route strings.

Parameters are automatically populated from the request body on POST and PUT
for form input, JSON and YAML content-types.

In the case of conflict between either of:

=over

=item *

route string parameters

=item *

GET, POST and PUT parameters

=item *

the contents of the request body on POST and PUT

=back

route string parameters will have precedence.

Query string and body parameters will be merged (see L<Plack::Request/parameters>)

=head3 Validation and coercion

You can define validations and coercion options for your parameters using a params block.

Parameters can be C<required> and C<optional>. C<optional> parameters can have a
default value.

    get params => [
        required => ['name', $Raisin::Types::String],
        optional => ['number', $Raisin::Types::Integer, 10],
    ],
    sub {
        my $params = shift;
        "$params->{number}: $params->{name}";
    };


Positional arguments:

=over

=item *

name

=item *

type

=item *

default value

=item *

regex

=back

Optional parameters can have a default value.

=head3 Types

Custom types

=over

=item *

L<Raisin::Types::Integer>

=item *

L<Raisin::Types::String>

=item *

L<Raisin::Types::Scalar>

=back

TODO
See L<Raisin::Types>, L<Raisin::Types::Base>

=head2 Hooks

This blocks can be executed before or after every API call, using
C<before>, C<after>, C<before_validation> and C<after_validation>.

Before and after callbacks execute in the following order:

=over

=item *

before

=item *

before_validation

=item *

after_validation

=item *

after

=back

The block applies to every API call

    before sub {
        my $self = shift;
        say $self->req->method . "\t" . $self->req->path;
    };

    after_validation sub {
        my $self = shift;
        say $self->res->body;
    };

Steps 3 and 4 only happen if validation succeeds.

=head1 API FORMATS

By default, Raisin supports C<YAML>, C<JSON>, and C<TXT> content-types.
The default format is C<TXT>.

Serialization takes place automatically. For example, you do not have to call
C<encode_json> in each C<JSON> API implementation.

Your API can declare which types to support by using C<api_format>.

    api_format 'JSON';

Custom formatters for existing and additional types can be defined with a
L<Raisin::Plugin::Format>.

Built-in formats are the following:

=over

=item *

C<JSON>: call JSON::encode_json.

=item *

C<YAML>: call YAML::Dump.

=item *

C<TXT>: call Data::Dumper->Dump if not SCALAR.

=back

The order for choosing the format is the following.

=over

=item *

Use the C<api_format> set by the C<api_format> option, if specified.

=item *

Default to C<TXT>.

=back

=head1 HEADERS

Use C<res> to set up response headers. See L<Plack::Response>.

    res->headers(['X-Application' => 'Raisin Application');

Use C<req> to read request headers. See L<Plack::Request>.

    req->header('X-Application');
    req->headers;

=head1 AUTHENTICATION

TODO
Built-in plugin L<Raisin::Plugin::Authentication>
L<Raisin::Plugin::Authentication::Basic>
L<Raisin::Plugin::Authentication::Digest>

=head1 LOGGING

Raisin has a buil-in logger based on Log::Dispatch. You can enable it by

    plugin 'Logger' => outputs => [['Screen', min_level => 'debug']];

See L<Raisin::Plugin::Logger>.

=head1 MIDDLEWARE

You can easily add any L<Plack> middleware to your application using
C<middleware> keyword.

=head1 PLUGINS

Raisin can be extended using custom I<modules>. Each new module must be a subclass
of the C<Raisin::Plugin> namespace. Modules' job is to initialize and register new
methods into the web application class.

For more see L<Raisin::Plugin>.

=head1 TESTING

TODO
L<Plack::Test>

=head1 DEPLOYING

See L<Plack::Builder>, L<Plack::App::URLMap>.

=head2 Kelp

    use Plack::Builder;
    use RaisinApp;
    use KelpApp;

    builder {
        mount '/' => KelpApp->new->run;
        mount '/api/rest' => RaisinApp->new;
    };

=head2 Dancer

    use Plack::Builder;
    use Dancer ':syntax';
    use Dancer::Handler;
    use RaisinApp;

    my $dancer = sub {
        setting appdir => '/home/dotcloud/current';
        load_app "My::App";
        Dancer::App->set_running_app("My::App");
        my $env = shift;
        Dancer::Handler->init_request_headers($env);
        my $req = Dancer::Request->new(env => $env);
        Dancer->dance($req);
    };

    builder {
        mount "/" => $dancer;
        mount '/api/rest' => RaisinApp->new;
    };

=head2 Mojolicious::Lite

    use Plack::Builder;
    use RaisinApp;

    builder {
        mount '/' => builder {
            enable 'Deflater';
            require 'my_mojolicious-lite_app.pl';
        };

        mount '/api/rest' => RaisinApp->new;
    };

=head1 GitHub

https://github.com/khrt/Raisin

=head1 AUTHOR

Artur Khabibullin - khrt <at> ya.ru

=head1 ACKNOWLEDGEMENTS

This module was inspired by L<Kelp>, which was inspired by L<Dancer>,
which in its turn was inspired by Sinatra.

=head1 LICENSE

This module and all the modules in this package are governed by the same license
as Perl itself.

=cut
