
use lib '/home/projects/cartv1';

package TransientHTMLTree;

use TransientBaby;

# use Nark; open $nl, '>', 'nark.log'; Nark::nark(sub { print $nl join ' ', @_, "\n"; });

sub new {
  my $me = {};
  my $pack = shift();
  my $fn = shift();
  bless $me, $pack;
};

%nonnesting_tags = map { $_ => 1 } qw(
  lit comment
  area base fontbase br col frame img input isindex link meta param
);
# %nonnesting_tags = map { $_ => 1 } qw(lit comment);

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

       while($current->get_next()) { $current = $current->get_next(); }; # xxx
       my $newnode = TransientHTMLTreeNode->new();
       print "debug: attaching node ", $newnode->get_nodenumber(), " next to (nonnest) ", $current->get_nodenumber(), "\n" if($debugf);
       $newnode->set_attribs(\%keyvals);
       $newnode->set_parent($current->get_parent());
       $current->set_next($newnode);
       $newnode->set_previous($current);
       $current = $newnode;

    } else {
       # the current tag can have children and enclose things. hang off of it.

       my $newnode = TransientHTMLTreeNode->new();
       $newnode->set_parent($current);
       $newnode->set_attribs(\%keyvals);
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
$allnodes = {};

sub new {
  my $pack = shift();
  my $me = {@_};
  $me->{'nodenumber'} = $nodenumber;
  $nodenumber++;
  bless $me, $pack;
  $allnodes->{$nodenumber} = $me;
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
  if(defined $repl) {
    $me->get_attribs()->{$att} = $repl;
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
  # iteratively derefrence "lit" nodes untill a non-lit node is found
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

sub unshift_content {
  my $me = shift;
  my $text = shift;
  my $newnode = TransientHTMLTreeNode->new();
  $newnode->set_attribs({tag=>'lit', text=>$text});
  $newnode->set_next($me->get_child());
  $newnode->set_previous(undef);
  $newnode->set_parent($me);
  if($me->get_child()) {
    $me->get_child()->set_previous($newnode);
  }
  $me->set_child($newnode);
  return 1;
}

sub push_content {
  my $me = shift;
  my $text = shift;
  my $node = $me->get_child();
  my $lastnode;

  my $newnode = TransientHTMLTreeNode->new();
  $newnode->set_attribs({tag=>'lit', text=>$text});
  $newnode->set_parent($me);

  if($node) {
    while($node and $node->get_attribs()->{tag} eq 'lit') {
      $lastnode = $node;
      $node = $node->get_next();
    }
    # first non-lit tag: insert before. $lastnode<->$newnode<->$node
    $newnode->set_next($node);
    $newnode->set_previous($lastnode);
    $node->set_previous($newnode) if($node);
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
  my $me = shift;
  my $parent = $me->get_parent();
  my $prev = $me->get_previous();
  my $next = $me->get_next();
  my $child = $me->get_child();
  if($child) {
    $parent->set_child($child) unless($prev);
    $prev->set_next($child) if($prev);
    $child->set_previous($prev);
    $child->set_parent($parent);
    $child->set_next($next);
    $next->set_previous($child) if($next);
  } else {
    return $me->delete_node();
  }
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
