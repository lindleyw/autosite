#!/usr/bin/perl

package TransientBaby;

# transient got way out of control.
# this seperates out the administrative and datasharing functionality from
# the core macro parser and macro generator functionality.

# TODO

# get prototyped aliases going for the create* functions, that take two args, like:
# query myfunkycoolquery "select * from bar where foo=FOO";
# or..
# form '<input type="text" name="color">';

# make all of the create* things plugin modules. use them. keep a list of @PLUGINS.
# make it easily extensible.

# removed contactdesigns. references from SQL. in the future, to facilitate multiple
# carts on one server, something similiar should be readded... perhaps a config
# variable read from $ENV{} that tells which database to look in. does postgres
# support the db.table.field syntax? it must...

# create* modules should take arg to override $callerpackage for reuse
# from other modules which create modules on the behalf of other modules.

# createcache createcattemplate

# list of external registered create* routines
# similiar to normal create* routines, these take one arg, the text of the object to create,
# the package to work within, and the name to give it. the create routine should create
# an object in that namespace to perform whichever action.
# args: package, name, text

my %PLUGINS;

sub add_plugin {
  die unless ref $_[1] eq 'CODE';
  $PLUGINS{$_[0]} = $_[1];
}

#use Lore qw(dbh);
#use Mail::Sendmail; # XXX - use from expansion module

my $modulename = 'TransientBaby';
my $debug=0;

use strict;
no strict 'refs';

my $macro = qr{\[:([a-z][a-z0-9_]+):\]};  # macros escaped by [::]
#my $macro = qr{([A-Z]{4,})}; # all caps macros

sub import {
  # were taking advantage of the fact that 'use TransientBaby' invokes this at compile time.
  # we want our create methods to be available in the using package so that they may use
  # them immediately.
  my $callerpackage = caller; 

  # my %args = @_;

  # begin action generators
  
  my $createvariable = sub {
    # this one is a bit different. this isnt compiled in our namespace.
    my $tname = lc(shift);
    my $ttext = shift;
    ${$callerpackage.'::'.$tname} = $ttext;
    # ${$callerpackage.'::sharelist'}{$tname} = 1;
  };
  
  my $createeval = sub { # action generator
    # create a symbol which when run evals some code and returns the result.
    my $n = lc(shift);          # SYMBOLNAME
    my $code = shift;           # Perl to be evaluated
    *{$callerpackage.'::'.$n} = sub {
      # $callerpackage is a lexical:
      # generated routine needs to know where we want it to think it is.
      my $ret = eval("package $callerpackage;\n" . $code); 
      if($@) { barf("eval-subtemplate failed: $@ <br>"); }
      return $ret;
    };
  };
    
  my $createcgi = sub { # action generator
    # create a symbol which when run reads the named cgi variables into our namespace.
    # this combines nicely with a cache or query.
    my $n = lc(shift());        # SYMBOLNAME
    my $varlist = lc(shift());  # list of symbols to read
    *{$callerpackage.'::'.$n} = sub {
      foreach my $i (split /\s+/, $varlist) {
        ${$callerpackage.'::'.$i} = CGI::param($i);
        # print "debug: reading from cgi variable: $i: ".${$callerpackage.'::'.$i}."<br>\n";
      }
    };
  };
    
  my $createcache = sub { # action generator
     # create two symbol which respectively store and retreive data from a users profile.
     # the 'data' in this case, is the variables and their values, taken from a list.
     # new, third symbol is created to zero out the cache.
     my $n = 'cache'.lc(shift);  # cachesymbolname
     my $o = 'un'.$n;            # uncachesymbolname
     my $p = 'zero'.$n;          # zerocachesymbolname
     my $varlist = lc(shift());  # list of symbols to save/restore
     *$n = sub {
       # cache
       barf("session untied... sigh...") unless(tied(%GrokMe::session));
       foreach my $i (split /\s+/, $varlist) { 
         # print "debug: caching variable: $i: $$i<br>\n";
         $GrokMe::session{$i} = ${$callerpackage.'::'.$i}; 
       }
     };
     *$o = sub {
       # uncache
       foreach my $i (split /\s+/, $varlist) {
         ${$callerpackage.'::'.$i} = $GrokMe::session{$i};
         # print "debug: uncaching variable: $i: $$i<br>\n";
       }
     };
     *$p = sub {
       # zerocache
       foreach my $i (split /\s+/, $varlist) {
         $GrokMe::session{$i} = '';
       }
     };
  };
    
  my $createtest = sub { # action generator
    # create a symbol which tests a variable, and evaluates to another specified symbol depending.
    # this is kind of stupid.
    my $n = lc(shift);  # SYMBOLNAME
    # variable to test, conditionally executed macros: successmacro, failmacro
    my ($varref, $onsuccess, $onfail) = split(/\s+/, shift);
    *{$callerpackage.'::'.$n} = sub {
      return &{$callerpackage.'::'.$onsuccess} if(${$callerpackage.'::'.$varref});
      return &{$callerpackage.'::'.$onfail};
    };
  };
    
  my $createsubtemplate = sub { # action generator
    # create a symbol which evaluates to the text we get here, run through the templator
    my $n = lc(shift);  # SYMBOLNAME
    my $text = shift;   # data
    *{$callerpackage.'::'.$n} = sub {
      return parse_macros($text, $n, $callerpackage);
    };
  };

  my $createform = sub { # action generator
    # create a symbol which evaluates to the text we get here, run through both
    # the templator and the form repopulator (and also the query evaluator)
    my $n = lc(shift);  # SYMBOLNAME
    my $text = shift;   # data
    *{$callerpackage.'::'.$n} = sub {
      return parse_form($text, $n, $callerpackage);
    };
  };
    
  my $createfileform = sub { # action generator
    # create a symbol which evaluates to the text we read from file, run through
    # both the form-repopulator and the macro expander
    my $n = lc(shift);  # SYMBOLNAME
    my $fn = shift;     # filename
    # XXX, todo, -M the file, and see if it is newer then our copy...
    # ie, do all of this conditionally
    local *F;
    open(F, $fn) or barf(__PACKAGE__ . ": failed to open file '$fn': $!. cannot read form from file.");
    my $file = join '', <F>;
    close(F);
    barf(__PACKAGE__ . ": file read from '$fn' is empty! this will never do...") if(!$file);
    *{$callerpackage.'::'.$n} = sub {
      return parse_form($file, $n, $callerpackage);
    };
  };
    
  my $createfilesubtemplate = sub { # action generator
    # create a symbol which evaluates to a whole file, run through the templator
    my $n = lc(shift);  # SYMBOLNAME
    my $fn = shift;     # filename
    # todo, -M the file, and see if it is newer then our copy...
    # ie, do all of this conditionally
    local *F;
    open(F, $fn) or barf(__PACKAGE__ . ": failed to open file '$fn': $!. cannot read subtemplate from file.");;
    my $file = join '', <F>;
    close(F);
    barf(__PACKAGE__ . ": file read from '$fn' is empty! this will never do...") if(!$file);
    *{$callerpackage.'::'.$n} = sub {
      return parse_macros($file, $n, $callerpackage);
    };
  };
    
    
  # createchecktest('isvisa', \$cctype, "Visa");  # ISVISA will now return ' checked' if $cctype eq Visa
  my $createchecktest = sub { # action generator
    my $n = lc(shift);  # SYMBOLNAME
    my $vr = shift;     # variable reference
    my $str = shift;    # string that variable is compared to
    *{$callerpackage.'::'.$n} = sub {
      if(${$callerpackage.'::'.$vr} eq $str) { return ' checked'; } else { return ''; }
    };
  };
    
  my $createemail = sub { # action generator
    # create a symbol which when evaluated sends off an Internet email.
    # the text argument used to create the symbol is parsed as a subtemplate, and
    # then expected to have, minimally, To:, From:, and Subject:. any Mail::Sendmail arguments
    # should be valid headers. the headers appear at the top of the email text, with a blank
    # line seperating the body of the email.
    my $n = lc(shift);  # SYMBOLNAME
    my $text = shift;   # message to send
    *{$callerpackage.'::'.$n} = sub {
      my $cmd = shift;
      require Mail::Sendmail;
      my %mail; my $msg = parse_macros($text, $n, $callerpackage); 
      return $msg if($cmd eq 'preview');
      $msg =~ s/^[^A-Z]+//;
      $msg =~ s/^([A-Z][a-z]*): (.*?)\n/$mail{$1}=$2; '';/mge; $mail{'Message'} = $msg;
      Mail::Sendmail::sendmail(%mail) or 
        barf("<pre>Failed to send email message! $Mail::Sendmail::error, callerpackage: $callerpackage\nheaders:\n" .
          join('', map {qq{$_: $mail{$_}\n}} grep { $_ } keys %mail) .
          "\n</pre>\n"
        );
      return '';
    };
  };
    
  my $createcgiupload = sub { # action generator
    # accept file uploads.
    my $n = lc(shift);    # SYMBOLNAME
    my $fn = shift;       # field/variable name (gotta be the same).
    *{$callerpackage.'::'.$n} = sub {
      my $fh;
      my $varbak = ${$callerpackage.'::'.$fn}; # if there is no upload, dont clobber existing info.
      my $buffer;
      my $bytesread;
      ${$callerpackage.'::'.$fn}=undef;
      # $fh = CGI::param($fn); # this works with CGI before 2.47
      $fh = CGI::upload($fn); # this doesnt
      while ($bytesread=read($fh,$buffer,1024)) {
        ${$callerpackage.'::'.$fn} .= $buffer;
      }
      ${$callerpackage.'::'.$fn} = $varbak unless(${$callerpackage.'::'.$fn});
      return '';
    };
  };
  
  my $parse_macros_wrapper = sub {
    # thin wrapper for parse_macros() that remembers the caller
    return parse_macros($_[0], $callerpackage, $callerpackage);
  };

  my %exports = (
     parse_form =>  \&parse_form, 
     parse_html => \&parse_html,
     parse_macros => $parse_macros_wrapper, 
     createeval => $createeval, 
     createcgi => $createcgi, 
     createemail => $createemail,
     createcache => $createcache, 
     createtest => $createtest, 
     createsubtemplate => $createsubtemplate, 
     createmacro => $createsubtemplate, # alias
     createform => $createform,
     createfileform => $createfileform, 
     createfilesubtemplate => $createfilesubtemplate, 
     createchecktest => $createchecktest, 
     createcgiupload => $createcgiupload,
  );

  foreach my $i (keys %PLUGINS) {
    my $coderef = $PLUGINS{$i};
    $exports{$i} = sub {
      # pass the registered plugin the name, memorized package, and text
      $coderef->($callerpackage, @_);
    };
  }
  
  $exports{learn_creates} = sub {
    my $quasicaller = caller;
    foreach my $i (keys %exports) {
      *{$quasicaller.'::'.$i} = $exports{$i};
    }
  };

  foreach my $i (keys %exports) {
    *{$callerpackage.'::'.$i} = $exports{$i};
  }
  
}

sub set_macro_escape {
  die unless ref $_[0] eq 'Regexp';
  $macro = shift();
}

sub query_macro_escape {
  return $macro;
}

#
# error trapping and dumping
#

sub loog { print STDERR @_, "\n"; }

# food for thought... something like this, that gives current values of atts for objs,
# even if just accessing methods.
#  email       => \&createemail,
# Cat related
# createcattemplate(lc($tname), $ttext)                            if($ttype eq 'cattemplate');
# createoptionval(lc($tname), $ttext)                              if($ttype eq 'optionval');

#
# satellite modules to the module that use us sometimes need to use these functions to
# create methods in the module that uses us... 
#

# parse_macros - expand MACRO style things
# parse_form   - repopulate HTML forms against data

sub formmiddle { # templator
  my $accessor = shift;
  my %keyvals = @_;

  my $name = $keyvals{name};
  my $value = $keyvals{value};

  my $callbackref = $accessor->('callback');
  my $cp = ${$accessor->('callerpackage')};
  my $line = $keyvals{lit};

 #my $debugf = sub { my $text = $accessor->('text'); print "debug: tag: $keyvals{tag}  name: $name  value: $value  cp: $cp  text: $$text\n"; }; &$debugf;

  if($keyvals{tag} eq 'select') {
    # repopulate <select>'s
    my $var=$name;
    $$callbackref = sub {
      $accessor = shift; %keyvals = @_;
 #&$debugf;
      if($keyvals{tag} eq 'option') {
        # if the option doesn't have a value tag, use the text of the option as the value
        my $kiped;
        my $val = $keyvals{value}; 
        unless($val) { $val = $accessor->('trailing'); $kiped=$val; }
        $val =~s/\s+//g;
        my $cpvar = ${"${cp}::${var}"}; if($cpvar+0 != 0) { $cpvar = $cpvar+0; } # numify
#print "debug: cpvar is $cpvar<br>\n";
        return ${"${cp}::${var}"} eq $val ? qq{<option value="$val" selected>$kiped}
                                          : qq{<option value="$val">$kiped};
      } elsif($keyvals{tag} eq '/select') {
        $$callbackref = \&formmiddle;
        return undef;
      } else {
        # no-op
        return undef;
      }
    };
    return undef; 

  } elsif($keyvals{tag} eq 'input' && $keyvals{type} eq 'radio' && $name) {
    # if the radio doesnt have a name, use the trailing text
    if(${$cp.'::'.$name} eq $value) {
      return qq{<input type="radio" name="$name" value="$value" checked>};
    } else {
      return undef; # no-op
    }

  } elsif($keyvals{tag} eq 'input' && $keyvals{type} eq 'checkbox' && $name) {
    # if the checkbox doesnt have a name, use the trailing text
    if(${$cp.'::'.$name}) {
      return qq{<input type="checkbox" name="$name" checked>};
    } else {
      return undef; # no-op
    }

  } elsif($keyvals{tag} eq 'input' && $keyvals{type} eq 'text' && $name) {
    # repopulate text boxes
    if(${$cp.'::'.$name}) {
      $keyvals{value} = ${$cp.'::'.$name};
    }
    delete $keyvals{tag};
    my $ret = qq{<input };
    foreach my $i (sort keys %keyvals) { $ret .= qq{$i="$keyvals{$i}" } }; 
    $ret .= qq{>};
    return $ret;
    # return '<input ', map { qq{$_=$keyvals{$_}}; } keys(%keyvals), ' foo=bar>';

  } else {
    # default case, nop
    return undef;
  }
}

sub parse_form {
  # template - dynamic list of operations to perform on each line of the file.
  # it changes as the context of the information in the file changes.
  # global data makes us non reenterant and non reusable.
  my $file = shift;
  my $from = shift;
  my $cp = shift; $cp ||= caller;      # generated functions bind to and pass their target package

  barf("$modulename: file '$file' is 0/blank/undef! oh, horrible day! '$from' invoked us.") unless($file);
  # do parse_macros() before split, so that replacements to multi lines get split.
  $file = parse_macros($file, $from, $cp); 
  my $line;
  my $todo;
  #my $ref=[\&formmiddle, $cp, undef];
  # return join "\n", map { $ref->[2]=$_; @_=($ref); $ref = &{$ref->[0]}; $ref->[2]; } split/\n/, $file;
  return parse_html($file, \&formmiddle, $cp);
}

sub parse_macros { # templator

  # replace "macros" with the
  # value of the function or variable of the same name (except lowercase).
  # this is invoked many places, but mostly from the functions generated to
  # handle invocations of macros (that have the same name as the macro).

  my $file = shift;       # the data to parse
  my $macroname = shift;  # for sake of error reporting, which symbol we are doing
  my $cp = shift;         # generated functions bind to and pass their target package

  if($cp and ! scalar %{$cp.'::'}) {
    die "the third argument to parse_macros() must be the name of a package";
  }
  $cp ||= scalar caller;

  if(!$file) {
    loog("parse_macros: warning: this template is empty. you probably really should fill in something for this template... '$macroname'");
    return '';
  }
  $file =~ s{$macro}{    # ... 5.004 has issues with this, doesnt like qr//
    # print "debug: looking for $1 callerpackage is $cp<br>\n";
    if(defined &{$cp.'::'.lc($1)}) {
      &{$cp.'::'.lc($1)}; # loog("invoking $1 from $macroname");
    } else { 
      ${$cp.'::'.lc($1)};
    }
  }egs;
  return $file;
}

# this is safer, but requires CGI 2.47, which production doesnt run yet
#            $fh = $query->upload('uploaded_file');
#            while (<$fh>) {
#                  print;
#            }

sub recursehashout { # utility
  (my $hashref, my $depth) = @_;
  my $ret;
  if(!$depth) { return "{\n" . recursehashout($hashref, 2) . "};\n"; }
  foreach my $i (keys %{$hashref}) {
    if(ref($hashref->{$i}) eq 'HASH') { 
      $ret .= ' ' x $depth . $i . " => {\n" . recursehashout($hashref->{$i}, $depth+2) . ' ' x $depth . "}\n"; 
    }
    else { $ret .= ' ' x $depth . $i . '=>' . $hashref->{$i} . ",\n"; }
  } 
  return $ret;
} 

# parse HTML, give callsbacks on each tag

sub parse_html {
  my $file = shift;
  my $callback = shift; $callback ||= sub { return 0; };
  my $callerpackage = shift;

  # if $callback->($accessor, %namevaluepairs) returns true, we use that return value in
  # place of the text that triggered the callback, allowing the callback to filter the HTML.

  my $name;
  my $text;
  my $state;     # 0-outside of tag; 1-inside of tag; 2-expecting name of new section
  my %keyvals;
  my $highwater; # where in the text the last tag started

  my $accessor = sub {
    my $var = shift;
    return \$file if($var eq 'file');
    return \$name if($var eq 'name');
    return \$text if($var eq 'text');
    return \$state if($var eq 'state');
    return \$callback if($var eq 'callback');
    return \$callerpackage if($var eq 'callerpackage');
    if($var eq 'trailing') { $file =~ m{\G([^<]+)}sgc; return $1; }
  };

  eval { while(1) {

    if($file =~ m{\G(<!--.*?-->)}sgc) {
      $text .= $1;
      print "debug: comment\n" if($debug);
      my $x = $callback->($accessor, tag=>'comment', text=>$1); if(defined $x) {
        $text .= $x;
      } else {
        $text .= $1;
      }

    } elsif($file =~ m{\G<([a-z0-9]+)}isgc) {
      # start of tag
      print "debug: tag-start\n" if($debug);
      $highwater = length($text);
      %keyvals = (tag => lc($1));
      $state=1;
      if(lc($1) eq 'div') {
        $state=2;
      } 
      $text .= "<" . cc($1);

    } elsif($file =~ m{\G<(/[a-z0-9]*)>}isgc) {
      # end tag
      $keyvals{'tag'} = lc($1);
      my $x = $callback->($accessor, %keyvals); if(defined $x) {
        $text .= $x;
      } else {
        $text .= "<".cc($1).">";
      }
      %keyvals=();
      print "debug: end-tag\n" if($debug);

    } elsif($file =~ m{\G(\s+)}sgc) {
      # whitespace, in or outside of tags
      if($state == 0) {
        my $x = $callback->($accessor, tag=>'lit', text=>$1); if(defined $x) {
          $text .= $x;
        } else {
          $text .= $1;
        }
      } else {
        $text .= $1;
      }
      print "debug: whitespace\n" if($debug);

    } elsif(($state == 1 || $state == 2) and
            ($file =~ m{\G([a-z0-9_-]+)\s*=\s*(['"])(.*?)\2}isgc or
             $file =~ m{\G([a-z0-9_-]+)\s*=\s*()([^ >]*)}isgc)) {
      # name=value pair, where value may or may not be quoted
      $keyvals{lc($1)} = $3;
      $text .= cc($1) . qq{="$3"}; # XXX need to preserve whitespace
      print "debug: name-value pair\n" if($debug);

    } elsif(($state == 1 || $state == 2) and
            ($file =~ m{\G([a-z0-9_-]+)}isgc)) {
      # name without a =value attached. if above doesnt match this is the fallthrough.
      $keyvals{lc($1)} = 1;
      $text .= cc($1); # correct case if needed
      print "debug: name-value pair without a value\n" if($debug);

    # } elsif($state == 1 and $file =~ m{\G>}sgc) {
    } elsif($file =~ m{\G>}sgc) {
      # end of tag
      $state=0;
      my $x = $callback->($accessor, %keyvals); if(defined $x) {
        # overwrite the output with callback's return, starting from the beginning of the tag
        # $text may have changed (or been deleted) since $highwater was recorded
        substr($text, $highwater) = $x if($highwater && length($text) > $highwater);
      } else {
        $text .= '>';
      }
      print "debug: tag-end\n" if($debug);

 #   } elsif($state == 1 and $file =~ m{\G/>}sgc) {
 #     # self closing tag end - test this
 #     $state=0;
 #     my $x = $callback->($accessor, %keyvals) || undef; # start tag...
 #     $keyvals{'tag'} = '/'.$keyvals{'tag'};
 #     my $y = $callback->($accessor, %keyvals) || undef; # and end tag.
 #     if($x.$y) {
 #       # overwrite the output with callback's return, starting from the beginning of the tag
 #       # $text may have changed (or been deleted) since $highwater was recorded
 #       substr($text, $highwater) = $x.$y if($highwater && length($text) > $highwater);
 #     } else {
 #       $text .= '/>';
 #     }
 #     print "debug: self-closing-tag\n" if($debug);

    } elsif($file =~ m{\G([^<]+)}sgc and $state != 1) {
      # between tag literal data
      # $text .= $1 unless($state == 2);
      my $x = $callback->($accessor, tag=>'lit', text=>$1); if(defined $x) {
        $text .= $x;
      } else {
        $text .= $1;
      }
      print "debug: lit data\n" if($debug);

    } elsif($file =~ m{\G<!([^>]+)}sgc and $state != 1) {
      # DTD 
      print "debug: dtd\n" if($debug);
      $highwater = length($text);
      $text .= '<!' . cc($1);
      %keyvals = (tag => lc($1));
      $state=1;

    } elsif($file =~ m{($macro)}sgc) {  # 5.004 has issues with this
      # an escape of whatever format we're using for escapes
      print "debug: template escape\n" if($debug);
      # XXX if this appears in a tag, no mention will be passed to handler,
      # which may rewrite the tag wtihout it
      $text .= $1;

    } else {
      # this should only ever happen on end-of-string, or we have a logic error
      (my $foo) = $file =~ m{\G(.*)}sgc;
      print "stopped at: -->$foo\n" if($debug);
      if($foo) {
        # this is an error condition
        $callback->($accessor, tag=>'stopped', text=>$foo) 
      }
      # else {
      #  # this is not
      #  $callback->($accessor, tag=>'eof');
      #} else {
      #}
      # nothing more to match
      # if($debug && $foo) { die("stopped with text remaining: $foo"); }
      return $text;
    }
  } };
  # shouldnt reach this point
  print $@ if($debug && $@);
  return $text;
}

sub cc {
  # cruft case
  # this is here so that we can easily turn on/off munging HTML to lowercase as needed, and yes, we have needed to
  # lower-case it...
  return lc(shift);
}

sub barf {
  die @_;
}

1;

# misc spam....

# bug - <javascript> should put us in a state to treat everything as text until </javascript>.
# this applies to other tags as well, probably.

#
# about this software:
#
# author: scott walters
# developed further for wlindely.com
# developed for contact designs, www.contactdesigns.com
# original version for world class websites (haha), www.wcws.com
#
