package Dancer::Plugin::FlashNote;

# ABSTRACT: support notifications in your Dancer web application

use strict;
use warnings;
use Carp;

use Dancer ':syntax';
use Dancer::Plugin;

my $conf = plugin_setting;

my %is_allowed_setting = map { $_ => 1 }
  qw( token_name session_hash_key queue arguments dequeue );
if (my @extra = grep { !$is_allowed_setting{$_} } keys %$conf) {
   croak __PACKAGE__ . ": invalid configuration keys (@extra)";
}

my $token_name       = $conf->{token_name}       || 'flash';
my $session_hash_key = $conf->{session_hash_key} || '_flash';
my $queue            = $conf->{queue}            || 'multiple';
my $arguments        = $conf->{arguments}        || 'auto';
my $dequeue          = $conf->{dequeue}          || 'when_used';

$arguments =~ m{\A(?: single | join | auto | array )\z}mxs
  or croak "invalid arguments setting '$arguments'";

sub _get_parameters {
   if ($arguments eq 'single') { return shift }
   elsif ($arguments eq 'join') { return join $, || '', @_ }
   elsif ($arguments eq 'array') { return [@_] }
   return @_ > 1 ? [@_] : shift;
} ## end sub _get_parameters

if ($queue eq 'single') {
   register flash => sub {
      my $value = _get_parameters(@_);
      session $session_hash_key, $value;
      return $value;
   };
} ## end if ($queue eq 'single')
elsif ($queue eq 'multiple') {
   register flash => sub {
      my $value = _get_parameters(@_);
      my $flash = session($session_hash_key) || [];
      push @$flash, $value;
      session($session_hash_key, $flash);
      return $value;
   };
} ## end elsif ($queue eq 'multiple')
elsif ($queue eq 'key_single') {
   register flash => sub {
      my $key   = shift;
      my $value = _get_parameters(@_);
      my $flash = session($session_hash_key) || {};
      $flash->{$key} = $value;
      session($session_hash_key, $flash);
      return $value;
   };
} ## end elsif ($queue eq 'key_single')
elsif ($queue eq 'key_multiple') {
   register flash => sub {
      my $key   = shift;
      my $value = _get_parameters(@_);
      my $flash = session($session_hash_key) || {};
      push @{$flash->{$key}}, $value;
      session($session_hash_key, $flash);
      return $value;
   };
} ## end elsif ($queue eq 'key_multiple')
else {
   croak "invalid queueing style '$queue'";
}

if ($dequeue eq 'by_key' and $queue !~ m{\Akey_}mxs) {
   croak "dequeuing style 'by_key' only available "
     . "with 'key_*' queueing styles";
}
if ($dequeue eq 'always') {
   hook after => sub {
      session $session_hash_key, undef;
   };
}
my $template_sub = {
   never => sub {
      shift->{$token_name} = session $session_hash_key;
      return;
   },
   always => sub {
      shift->{$token_name} = session $session_hash_key;
      return;
   },
   when_used => sub {
      my $cache;
      shift->{$token_name} = sub {
         if (!$cache) {
            $cache = session $session_hash_key;
            session $session_hash_key, undef;
         }
         return $cache;
      };
      return;
   },
   by_key => sub {
      my $flash = session($session_hash_key) || {};
      shift->{$token_name} = {
         map {
            my $key = $_;
            my $cache;
            $key => sub {
               if (!$cache) {
                  $cache = delete $flash->{$key};
               }
               return $cache;
            };
           } keys %$flash,
      };
   },
  }->{$dequeue}
  or croak "invalid dequeuing style '$dequeue'";
hook before_template => $template_sub;

register flash_flush => sub {
   my $flash = session $session_hash_key;
   return unless defined $flash;
   if ((ref($flash) eq 'HASH') && @_) {
      my @values = map { delete $flash->{$_} } @_;
      return unless defined wantarray();
      return $values[0] unless wantarray();
      return @values;
   } ## end if ((ref($flash) eq 'HASH'...
   else {
      session $session_hash_key, undef;
      return $flash;
   }
};

register_plugin;

1;

__END__

=pod

=head1 SYNOPSIS

   # In the configuration you choose a "flash style", e.g.
   # notifications stored in an array and automatically
   # removed from the session when used
   plugins:
      FlashNote:
         queue:   multiple
         dequeue: when_used


   # In the application you generate flash notifications
   package MyWebService;

   use Dancer;
   use Dancer::Plugin::FlashNote;

   get '/hello/:id/:who' => sub {
      flash 'A first error message'
         unless params->{id} =~ /\A\d+\z/mxs;
      flash 'A second error message'
         unless params->{who} =~ /\A(?: you | me )\z/mxs;
      # ...
      template 'index';
   };


   # Then, in the layout you consume them and they are flushed
   <% IF flash %>
      <ul class="error">
      <% FOR notice = flash %>
         <li><% notice | html %></li>
      <% END %>
      </ul>
   <% END %>



=head1 DESCRIPTION

This plugin helps you display temporary messages, so called "flash messages".
It provides a C<flash()> method to define the message. The plugin then takes
care of attaching the content to the session, propagating it to the templating
system, and then removing it from the session. On the other hand, you still
have to take care to find a suitable place to put the messages.


=head2 Dancer::Plugin::FlashMessage

This plugin originages from L<Dancer::Plugin::FlashMessage> by
Damien "dams" Krotkine. While I appreciated the idea and the implementation,
I felt that the way of use did not fit my needs and after some discussion
we decided to go for different modules: he would retain only the one
single behaviour that he thought was the best, and I would implement the
different variations. I learned a lot from the discussion, so beware: the
Dancer people can teach you a lot!

This configuration should give you a behaviour equivalent to
L<Dancer::Plugin::FlashMessage>:

  plugins:
    FlashNote:
      queue:     key_single
      arguments: single
      dequeue:   by_key

but if you need it you can probably stick to L<Dancer::Plugin::FlashMessage>.
Also note that with the configuration above the C<flash()> function will
not work in the same way as L<Dancer::Plugin::FlashMessage> when called
with only one parameter: in dams' module this kind of call deletes the
value associated to the key, in this module this just pushes an undef
message.

=head2 Styles

Dancer::Plugin::FlashNote lets you decide the I<style> of how you want to handle
your flash notifications. Different applications - in particular when the
difference is in their size - might need different styles, e.g.:

=over

=item *

a small application that you want to use in a restricted group of friends
has little needs. In this case, all you probably need is some way to
generate a notification message in your application and get it written
somewhere in the page:

   flash 'hey mate, you made an error! Check your inputs'
      unless params_are_ok();

=item *

a big application with internationalisation needs a more sophisticated
flash message approach. Generating feedback messages directly in the
controller is not a good idea, especially if you are giving feedback about
wrong values provided by the User and you want to display these values
within your message. In other terms, if you put this in the controller:

   my $value = params->{id};
   flash "The id value '$value' is not allowed"
      unless $value =~ /\A\d+\z/mxs;

you'll have a hard time to translate the message. The best approach in
this case is to set a message identifier that can possibly select a
template or a string, and provide the parameters:

   # In the controller
   my $value = params->{id};
   flash value_not_allowed => id => $value;

   # In the template, probably the layout
   <%
      FOR note = flash;
         type = note.0;
         INCLUDE "flash/$lang/$type.tt", note = note;
      END;
   %>

   # flash/en/value_not_allowed.tt
   The [% note.1 %] value '[% note.2 | html %]' is not allowed

   # flash/it/value_not_allowed.tt
   Il parametro [% note.1 %] non ammette il
   valore '[% note.2 | html %]'

=item *

an application might want to keep separate "channels" for different
kind of notifications (e.g. warnings, errors, simple info), while
still keeping a list of messages for each channel;

=back

and so forth.

The different needs addressed by this module deal with three areas:

=over

=item *

how flash messages are queued for later usage from the template. This
can be decided through the C<queue> configuration, and changes the
semantics of the C<flash()> function and how its parameters are
used;

=item *

how multiple parameters to any single call to the C<flash()> function
are handled;

=item *

how flash messages are flushed away. Messages are stored in a session
in order to "survive" redirections and be still there when a template
has the occasion to display them, but at that point you can decide that
the module can get rid of them (automatically, of course).

=back

By default, messages are kept as a plain list in the order they are
queued by the controller, i.e. in the same order of each call to the
C<flash()> function. Multiple parameters are simply joined together
using C<$,> (i.e. like C<warn()>, C<die()> etc.) and all the messages
are flushed away after they get the occasion to be displayed.




=head1 INTERFACE

=head2 flash

  # sets the flash message for the warning key
  flash warning => 'some warning message';

This method inserts a flash message in the cache. What it puts inside and in
what manner depends on the queueing method, see below L</Queueing Styles>. By
default, it accepts one or more parameters and they are queued inside an
array as a scalar (in case of one parameter) or as an array reference.

The method always returns the provided message.

=head2 flash_flush

Flush the flash messages.

   # flushes the whole flash cache, returning it
   my $flash = flash_flush();

   # if queuing method is a "key_*", flushes selected keys
   my @values = flash_flush(qw( warning error ));

You should not need to use this function if you set a proper dequeue
style and display the messages.


=head1 CONFIGURATION

Configurations are used only when the module is loaded, so take care
to place them in a configuration file or before C<use>-ing the module.

=head2 Configuration Default Values

The module works also without configurations, the following sample
configuration includes all the default values:

  plugins:
    FlashNote:
      token_name:       flash
      session_hash_key: _flash
      queue:            multiple
      arguments:        auto
      dequeue:          when_used

See the following section for an explanation of the keys.

=head2 Options

=over

=item token_name

The name of the template token that will contain the hash of flash messages.
B<Default>: C<flash>.

=item session_hash_key

You probably don't need that, but this setting allows you to change
the name of the session key used to store the hash of flash messages.
It may be useful in the unlikely case where you have key name conflicts
in your session. B<Default>: C<_flash>.

=item queue

Sets the queueing style to one of the following allowed values:

=over

=item -

single

=item -

multiple

=item -

key_single

=item -

key_multiple

=back

See L</Queueing Styles> below for the details. B<Default>: C<multiple>.

=item arguments

Sets how multiple values in a call to C<flash> should be handled. The
allowed values for this options are the following:

=over

=item -

single

=item -

join

=item -

auto

=item -

array

=back

See L</Multiple Parameters> below for the details. B<Default>: C<auto>.

=item dequeue

Sets the dequeueing style to one of the following allowed values:

=over

=item -

never

=item -

always

=item -

when_used

=item -

by_key

=back

See L</Dequeueing Styles> below for the details. B<Default>: C<when_used>.

=back

=head2 Queueing Styles

There are various styles for setting flash messages, which are
explained in the following list. The assumption in the documentation is
that the C<token_name> configuration is equal to the default C<flash>,
otherwise you have to substitute C<flash> with what you actually set.

The queueing style can be set with the C<queue> configuration, with
the following allowed values:

=over

=item B<< single >>

   flash $message;

this is the simplest style, one single message can be hold at any time.
The following call:

   flash 'hey you!';
   # ... later on...
   flash 'foo! bar!';

will replace any previously set message. In the template,
you will be able to get the latest set value with the C<flash> token:

   flash => 'foo! bar!'

=item B<< multiple >>

   flash $message;
   flash $other_message;

multiple messages are queued in the same order as they are put. The
following call:

   flash 'hey you!';
   # ... later on...
   flash 'foo! bar!';

will add C<$message> to the queue, and what you get in the template is
a reference to an array containing all the messages:

   flash => [
      'hey you!',
      'foo! bar!',
   ]

=item B<< key_single >>

   flash key1 => $message;
   flash key2 => $other_message;

you can have messages of different I<types> by providing a key, but only
one for each type. For example, you can set a I<warning> and an I<error>:

   flash warning => 'beware!';
   # ... later on...
   flash error => 'you made an error...';
   # ... and then...
   flash warning => 'ouch!';

Any further call to C<flash> with an already used key substitutes the
previous message with the new one.

In this case, the C<flash> token in the template returns an hash with
the keys you set and the last message introduced for each key:

   flash => {
      error   => 'you made an error...',
      warning => 'ouch!',
   }

=item B<< key_multiple >>

   flash key1 => $message;
   flash key2 => $other_message;
   flash key1 => $yet_another_message; # note key1 again

you can have messages of different I<types> by providing a key, and all
of them are saved. In the following example:

   flash warning => 'beware!';
   # ... later on...
   flash error => 'you made an error...';
   # ... and then...
   flash warning => 'ouch!';

In this case, the C<flash> token in the template returns an hash of
arrays, each containing the full queue for the particular key:

   flash => {
      error   => [ 'you made an error...' ],
      warning => [
         'beware!',
         'ouch!'
      ],
   }

In your template:

   <% IF flash %>
      <ul class="messages">
      <% FOR message = flash.pairs %>
        <% FOR text = message.value %>
         <li class="[% message.key | html %]"><% text | html %></li>
        <% END %>
      <% END %>
      </ul>
   <% END %>

Becomes:

    <ul class="messages">
        <li class="error">you made an error...</li>
        <li class="warning">beware!</li>
        <li class="warning">ouch!</li>
    </ul>

=back

The default queueing style is I<multiple>.

=head2 Multiple Parameters

The queueing style is not the entire story, anyway. If you provide more
parameters after
the C<$message>, this and all the following parameters are put in an anonymous
array and this is set as the new C<$message>. Assuming the C<simple> queueing
style, the following call:

   flash qw( whatever you want );

actually gives you this in the template token:

   flash => [ 'whatever', 'you', 'want' ];

This is useful if you don't want to provide a I<message>, but only parameters to be
used in the template to build up a message, which can be handy if you plan to make
translations of your templates. Consider the case that you have a parameter in a
form that does not pass the validation, and you want to flash a message about it;
the simplest case is to use this:

   flash "error in the email parameter: '$input' is not valid"

but this ties you to English. On the other hand, you could call:

   flash email => $input;

and then, in the template, put something like this:

   error in the <% flash.0 %> parameter: '<% flash.1 %>' is not valid

which lets you handle translations easily, e.g.:

   errore nel parametro <% flash.0 %>: '<% flash.1 %>' non valido

If you choose to use this, you might find the C<arguments> configuration handy.
Assuming the C<multiple> queueing style and the following calls in the code:

   # in the code
   flash 'whatever';
   flash hey => 'you!';

you can set C<arguments> in the following ways:

=over

=item B<< single >>

this always ignores parameters after the first one. In the template, you get:

   flash => [
      'whatever',
      'hey',       # 'you!' was ignored
   ]

=item B<< join >>

this merges the parameters using C<$,> before enqueueing the message. In the
example, you get this in the template:

   flash => [
      'whatever',
      'heyyou!',   # join with $,
   ]

=item B<< auto >>

this auto-selects the best option, i.e. it puts the single argument as-is if there
is only one, otherwise generates an anonymous array with all of them. In the
template you get:

   flash => [
      'whatever',
      [ 'hey', 'you!' ],
   ]

=item B<< array >>

this always set the array mode, i.e. you get an array also when there is only
one parameter. This is probably your best choice if you plan to use multiple
parameters, because you always get the same structure in the template:

   flash => [
      [ 'whatever' ],
      [ 'hey', 'you!' ],
   ]

=back

The default handling style is I<auto>.

=head2 Dequeueing Styles

When you put a message in the queue, it is kept in the User's session until it
is eventually dequeued. You can control how the message is deleted from the
session with the C<dequeue> parameter, with the following possibilities:

=over

=item B<< never >>

items are never deleted automatically, but they will be flushed in the code
by calling C<flash_flush()>;

=item B<< always >>

items are always deleted from the session within the same call. Technically
speaking, using the session in this case is a bit overkill, because the session
is only used as a mean to pass data from the code to the template;

=item B<< when_used >>

items are all deleted when any of them is used in some way from the template. The
underlying semantics here is that if you get the chance to show a flash message
in the template, you can show them all so they are removed from the session. If
for some reason you don't get this chance (e.g. because you are returning a
redirection, and the template rendering will happen in the next call) the
messages are kept in the session so that you can display them at the next
call that actually makes use of a template;

=item B<< by_key >>

this style only applies if the queueing style is either C<key_single> or C<key_multiple>.
It is an extension of the C<when_used> case, but only used keys are deleted and
the unused ones are kept in the session for usage at some later call.

=back

The default dequeuing style is I<when_used>.

=head1 DEPENDENCIES

Only L<Dancer> and the bundled module L<Dancer::Plugin>.

=head1 BUGS AND LIMITATIONS

Curious about active bugs or want to report one? The bug tracking system
can be found at L<https://rt.cpan.org/Public/Dist/Display.html?Name=Dancer-Plugin-FlashNote>.

=head1 SEE ALSO

If you want to contribute, check this module out in GitHub at
L<https://github.com/polettix/Dancer-Plugin-FlashNote>.

This module started from L<Dancer::Plugin::FlashMessage>, which is an
excellent module if its flash message style suits to your needs. You surely
recognised that some small parts of this documentation come from there.

And L<Dancer>, of course!

=cut
