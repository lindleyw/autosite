
use lib '/home/projects/cartv1';

package TransientHTMLTree;

use TransientBaby;

# use Nark; open $nl, '>', 'nark.log'; Nark::nark(sub { print $nl join ' ', @_, "\n"; });

sub new {
  my $me = {};
  my $pack = shift();
  my $copy_from = shift();
  bless $me, $pack;
  if ($copy_from) {
      $me->{root} = $copy_from->copy();
  }
  return $me;
};

%nonnesting_tags = map { $_ => 1 } qw(
  lit comment
  area base fontbase br col frame img input isindex link meta param
);
# %nonnesting_tags = map { $_ => 1 } qw(lit comment);

# wl 2003-11-04:
# There is code in TransientBaby to handle self-closing tags, e.g.:   <BR />
# which perhaps could be modified to set a key in the attribs hash like:
#    $current->set_attribs('/' -> 1);
# and which we could then set and use below along with %nonnesting_tags
# so that "<BR>" and "<BR />" would be handled the same... actually reading
# "<BR>" would create "<BR />" in the output which is (maybe?) a good thing.
# Or we could set_attribs('/', 'explicit') and set_attribs('/', 'implicit')
# so output would be the same as input.
# In either case, regen() and element_html() would have to respect the '/'.

sub parse {
  # build a tree

  my $me = shift();
  my $text = shift();

  my $root = TransientHTMLTreeNode->new();
  $root->set_attribs({});
  my $current = $root;

  my $accessor;

  parse_html($text, sub {
    $accessor = shift;
    my %keyvals = @_;

    print "debug: loop: ", $current->get_nodenumber(), "\n" if($debugf);

    if(substr($keyvals{tag}, 0, 1) eq '/') {
       # these tags unnest. they were children of current.

       my $probe = $current;
       my $endtag = substr($keyvals{tag}, 1);
       while($probe->get_attribs()->{tag} ne $endtag) {
         $probe = $probe->get_parent();
         # print "debug: looking for $endtag, have: ", $probe->get_attribs()->{tag}, " ", $probe->get_nodenumber(), "\n";
         die "end tag for $endtag not found!" unless $probe;
       }
       while($probe->get_next()) { $probe = $probe->get_next(); };

       my $newnode = TransientHTMLTreeNode->new();
       $newnode->set_attribs({tag=>$keyvals{tag}});
       $newnode->set_parent($probe->get_parent());
       $newnode->set_previous($probe);
       $probe->set_next($newnode);
       print "debug: attaching node ", $newnode->get_nodenumber(), " next to (closing) ", $probe->get_nodenumber(), "\n" if($debugf);
       $current = $probe->get_parent();
       while($current->get_next()) { $current = $current->get_next(); }; # xxx
       
    } elsif($current and $nonnesting_tags{$current->tag()}) {
        # the current tag can never have children and enclose things. dont nest.
       my $newnode = TransientHTMLTreeNode->new();
       $newnode->set_attribs(\%keyvals);
       $newnode->set_parent($current->get_parent());

       while($current->get_next()) { $current = $current->get_next(); }; # xxx
       print "debug: attaching node ", $newnode->get_nodenumber(), " next to (nonnest) ", $current->get_nodenumber(), "\n" if($debugf);

       $current->set_next($newnode);
       $newnode->set_previous($current);
       $current = $newnode;

    } else {
       # the current tag can have children and enclose things. hang off of it.
       my $newnode = TransientHTMLTreeNode->new();
       $newnode->set_attribs(\%keyvals);
       $newnode->set_parent($current);

       if(!$current->get_child()) {
         # first and only child
         $current->set_child($newnode) or die;
          # print join '', "debug: attaching node ", $newnode->get_attribs()->{'tag'}, ' ', $newnode->get_nodenumber(), " under ", $current->get_attribs()->{'tag'}, ' ', $current->get_nodenumber(), "\n";
         print "debug: attaching node ", $newnode->get_nodenumber(), " under ", $current->get_nodenumber(), "\n" if($debugf);
       } else {
         # find last child
         my $cursor = $current->get_child();
         while($cursor->get_next()) {
           $cursor = $cursor->get_next();
         }
         $cursor->set_next($newnode) or die;
         $newnode->set_previous($cursor) or die;
         print "debug: attaching node ", $newnode->get_nodenumber(), " next to ", $cursor->get_nodenumber(), "\n" if($debugf);
       }
       $current = $newnode;

    }

  });

  $me->{root} = $root;

  return $root;

};

sub traverse2 {
  # recurse our own tree
  my $me = shift();
  my $cb = shift();
  my $node = shift() || $me->{root}; die unless $node;
  my $level = shift() || 0;

  my $cursor = $node;
  while($cursor) {
    $cb->($cursor->get_attribs(), $level, $cursor);
    if($cursor->get_child()) {
      $me->traverse2($cb, $cursor->get_child(), $level+1);
    }
    $cursor = $cursor->get_next();
  }
 
  return 1; 

};

sub regen {
  # reconstruct the original HTML document, plus any modifications
  my $me = shift();
  my $node = shift() || $me->{root};

  my $html;

  my $tag; my $ob; my $tag; 

  $me->traverse2(sub {
    
    $tag = shift();
    $level = shift();
    $ob = shift();

    if($tag->{tag} eq 'lit' or
       $tag->{tag} eq 'comment') {
      $html .= $tag->{text};
    } elsif($tag->{tag}) {
      $html .= '<' . $tag->{tag};
      $html .= join '', map { qq{ $_="$tag->{$_}"} } sort grep { $_ ne 'tag' } keys %$tag;
      $html .= '>';
    }

  }, $node);

  return $html;
  
}

1;

#
# TransientHTMLTreeNode
#

package TransientHTMLTreeNode;

$nodenumber=1;

sub new {
  my $pack = shift();
  my $me = {@_};
  $me->{'nodenumber'} = $nodenumber;
  $nodenumber++;
  bless $me, $pack;
  return $me;
}

# accessors

foreach my $i (qw(parent child previous next attribs nodenumber)) {
  my $j = $i;
  *{"get_$j"} = sub { $_[0]->{$j}; };
  *{"set_$j"} = sub { $_[0]->{$j} = $_[1]; };
}

sub append_child {
  # add a child in front of our existing chlidren
  my $me = shift();
  my $kid = shift();
  if($me->get_child()) {
    return append_sibling($me->get_child(), $kid);
  } else {
    $me->get_child() = $kid;
  }
}

sub append_sibling {
  my $me = shift();
  my $newsib = shift();

  # find the end of the chain of nodes being added
  # may not be any other nodes in the chain - thats perfectly ok
  my $lastsib = $newsib;
  while($lastsib->get_next()) {
    $lastsib = $lastsib->get_next();
  };

  # insert the chain of siblings in after us
  # us->newsibs->oldsib
  my $oldsib = $me->get_next();
  $me->set_next($newsib); 
  $lastsib->set_next($oldsib);

  return 1;

}

# compatability methods

sub tag {
  my $me = shift();
  return $me->get_attribs()->{'tag'};
}

sub attr {
  my $me = shift();
  my $att = shift();
  my $repl = shift();
  while (defined $repl) { # multiple attribute replacements may be passed
      if (length($repl) == 0) {
	  delete $me->get_attribs()->{$att}; # remove attributes with empty text
      } else {
	  $me->get_attribs()->{$att} = $repl;
      }
      (my $nextatt, $repl) = (shift(), shift());
      $att = $nextatt if $nextatt;
  }
  return $me->get_attribs()->{$att};
}

sub parent {
  return $_[0]->get_parent();
}

sub delete_content {
  my $me = shift;
  my $all_content = shift;	# TRUE = all content, else literals only
  my $node = $me->get_child();
  # iteratively derefrence "lit" nodes until a non-lit node is found
  while($node and ($all_content or $node->get_attribs()->{tag} eq 'lit')) {
    $node = $node->get_next();
    if($node) {
      $node->set_previous(undef);
      $me->set_child($node);
    } else {
      $me->set_child(undef);
    }
  }
  return 1;
}

sub _content_node {
  my $text = shift;

  my $newnode;
  if (ref ($text)) {
      $newnode = $text; # move existing node into tree
  } else {
      # create a new text literal node
      $newnode = TransientHTMLTreeNode->new();
      $newnode->set_attribs({tag=>'lit', text=>$text});
  }
  return $newnode;
}

sub unshift_content {
  # Inserts text or a node as a child below the current node,
  # before any existing child nodes.
  my $me = shift;
  my $text = shift;

  my $newnode = _content_node($text);
  my $newtail = $newnode;
  while ($newtail->get_next()) {
      $newtail = $newtail->get_next();
      $newtail->set_parent($me);
  }
  $newnode->set_parent($me);

  $newtail->set_next($me->get_child());
  $newnode->set_previous(undef);
  if($me->get_child()) {
    $me->get_child()->set_previous($newtail);
  }
  $me->set_child($newnode);
  return 1;
}

sub push_content {
  # Inserts text or a node as a child below the current node,
  # after any existing child nodes.
  my $me = shift;
  my $text = shift;
  my $node = $me->get_child();
  my $lastnode;

  my $newnode = _content_node($text);
  my $newtail = $newnode;
  while ($newtail->get_next()) {
      $newtail = $newtail->get_next();
      $newtail->set_parent($me);
  }
  $newnode->set_parent($me);

  if($node) {
    while($node and $node->get_attribs()->{tag} eq 'lit') {
      $lastnode = $node;
      $node = $node->get_next();
    }
    # first non-lit tag: insert before. $lastnode<->$newnode<->$node
    $newtail->set_next($node);
    $node->set_previous($newtail) if($node);
    $newnode->set_previous($lastnode);
    if($lastnode) {
      $lastnode->set_next($newnode) 
    } else {
      $me->set_child($newnode);
    }
    # print "debug: inserting between ", $lastnode ? $lastnode->get_nodenumber() : 'none',
    #       " and ", $node ? $node->get_nodenumber() : 'none', "\n";
  } else {
    $me->set_child($newnode);
  }
  return 1;
}

sub delete_node {
  # Deletes a node and its children.
  my $me = shift;
  my $parent = $me->get_parent();
  my $prev = $me->get_previous();
  my $next = $me->get_next();
  if($prev) {
    $prev->set_next($next);
    $next->set_previous($prev) if($next);
  } else {
    $parent->set_child($next);
    $next->set_previous(undef) if($next);
  }
}

sub remove_node {
  # Deletes a node.  Its children, if any, take its place.
  my $me = shift;
  my $parent = $me->get_parent();
  my $prev = $me->get_previous();
  my $next = $me->get_next();
  my $child = $me->get_child();
  if($child) {
    if($prev) {
	$prev->set_next($child);
    } else {
	$parent->set_child($child);
    }
    $child->set_previous($prev);
    $child->set_parent($parent);
    $child->set_next($next);
    $next->set_previous($child) if($next);
  } else {
    return $me->delete_node();
  }
}

sub root {
  # Returns the node's root
  my $me = shift;
  while ($me->get_parent()) {
      $me = $me->get_parent();
  }
  return $me;
}

sub copy {
    # returns a copy of a node and its children
    my $me = shift;
    my $parent = shift;

    my $cursor = $me;           # source node
    my $new_node;               # destination node
    my $first_node;
    my $prev;                   # destination: previous node

    while($cursor) {

	$new_node = TransientHTMLTreeNode->new();

        # copy attributes by creating new anonymous hash
	$new_node->set_attribs({%{$cursor->get_attribs()}});
	#print join('|', %{$new_node->get_attribs()}), "\n";

	$new_node->set_parent($parent);                  # maintain parent relation
	$new_node->set_previous($prev);                      # doubly linked list
	if ($prev) {
	    $prev->set_next($new_node);
	} else {
	    $parent->set_child($new_node) if $parent;
	}
	if($cursor->get_child()) {                       # copy each of our children
	    $cursor->get_child()->copy($new_node);             # our 'me' will be parent of the new child
	}
	$prev = $new_node;                                 # we will be the previous node next time 'round
	$first_node = $new_node unless $first_node;
	$cursor = $cursor->get_next();
    }
 
    return $first_node; 
}

sub find {
  # finds a subnode based on criteria
  my $me = shift();
  my $match = shift(); # hash of criteria
  my $found;

  my $cursor = $me;
  while($cursor) {
    $found = $cursor;
    my %attribs = %{$cursor->get_attribs()};
    foreach  (keys %{$match}) {
      if ($attribs{$_} ne $match->{$_}) {
        $found = undef;
        last;
      }
    }
    return $found if $found;
    if($cursor->get_child()) {
      $found = $cursor->get_child()->find($match);
      return $found if $found;
    }
    $cursor = $cursor->get_next();
  }
 
  return undef;
}


sub get_previous_or_parent() {
  my $me = shift;
  return $me->{previous} if($me->{previous});
  return $me->{parent};
}

# Like sub from regen above; but note that the 'my $html' there is scoped to aggregate.
# this one returns the HTML for a single node alone.
sub element_html {

    my $me = shift();
    my $html;
    my $tag = $me->attr('tag');
    my $attribs;

    if($tag eq 'lit' or $tag eq 'comment') {
      $html .= $me->attr('text');
    } elsif($attribs = $me->get_attribs()) {
      $html .= '<' . $tag;
      $html .= join '', map { qq{ $_="$attribs->{$_}"} } sort grep { $_ ne 'tag' } keys %$attribs;
      $html .= '>';
    }
    
    return $html;
}

1;
