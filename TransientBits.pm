package TransientBits;

# deal with bits and peices of HTML

# we require that the package using us has already use'd Transient.
# by using the create functions generated for it, things are created in it's namespace.

my $name;
my $text;
my $state; # 0-outside of tag; 1-inside of tag; 2-expecting name of new section

$debug=0;

sub import {
  my $me = shift;
  my %args = @_;

  # while((my $i, my $j) = each(%args)) {
  #   print "args: $i $j\n";
  # }

  my $html = $args{'template_file'};

  open F, "<$html" or die "$html: $!"; my $file = join '', <F>; close F;

  if($debug) { die unless $html; }

  &{scalar(caller).'::learn_creates'};
  # gives us access to parse_html() and createsubtemplate()

  my $type; # type of object we're looking at

  parse_html($file, sub {
    my $accessor = shift;
    my %keyvals = @_;

    my $nameref = $accessor->('name');
    my $textref = $accessor->('text');

    print "** debug: tag: ", $keyvals{tag}, "  name: ", $$nameref, "\n" if($debug>1);

    # in the case of a div, we squirrel away anything we've buffered, and start 
    # buffering anew. div divides our HTML into names sections that get turned
    # into subtemplates. 

    # out with the old...
    if(lc($keyvals{'tag'}) eq '/div' && $$nameref) {
      createemail($$nameref, $$textref) if($type eq 'email');
      createform($$nameref, $$textref) if($type eq 'form');
      createsubtemplate($$nameref, $$textref) if($type eq 'macro');
      print "$$nameref\n" if($debug==1);
      print "\n\n$$nameref ...\n", $$textref, "\n" if($debug>1);
      return ' ';
    }

    # in with the new...
    if(lc($keyvals{'tag'}) eq 'div') {
      $$nameref = $keyvals{'id'};
      $type = $keyvals{'class'};
      $$textref = '';
      return ' ';
    }

    # shouldnt happen...
    if(lc($keyvals{'tag'}) eq 'stopped') {
      die "failed to parse template file $html: stopped at $keyvals{'text'}";
    }

    # do not modify HTML if tag not recognized
    return undef; 
  });

  # utility to remove all of the <table> and </tables> tags except the first and last, respectively

  *{scalar(caller).'::unatabler'} = sub {
    my $tablestart;
    my $tableend;
    parse_html(shift, sub {
      my $accessor = shift;
      my %keyvals = @_;
      my $textref = $accessor->('text');
    
      if(lc($keyvals{'tag'}) eq 'table') {
        if($tablestart) {
          # nuke duplicate table-start
          return ' ';
        } else {
          $tablestart = 1;
          return undef;
        }
      }
  
      if(lc($keyvals{'tag'}) eq '/table') {
        if($tableend) {
          # delete previous table-end
          pos($$textref) = $tableend;
          $$textref =~ s{\G</table.*?>}{}sig;
          $tableend = length($$textref);
          return undef;
        } else {
          $tableend = length($$textref);
        }
      }
  
      return undef; # unknown tag. do nothing.
      
    }, scalar(caller));
  };
  
}

1;
