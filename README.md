NAME
====

Dancer::Plugin::FlashNote - support notifications in your Dancer web
application

SYNOPSIS
========

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

ALL THE REST
============

Want to know more? [See the module’s documentation](http://search.cpan.org/perldoc?Dancer::Plugin::FlashNote) to figure out
all the bells and whistles of this module!

Want to install the latest release? [Go fetch it on CPAN](http://search.cpan.org/dist/Dancer-Plugin-FlashNote/).

Want to contribute? [Fork it on GitHub](https://github.com/polettix/Dancer-Plugin-FlashNote).

That’s all folks!
