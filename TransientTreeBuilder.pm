# this is a drop-in incomplete replacement for HTML::TreeBuilder.
# it uses TransientHTMLTree which uses TransientBaby, and adapts
# TransientHTMLTree to provide the same interface as HTML::TreeBuilder.

package TransientTreeBuilder;

use TransientHTMLTree;
@ISA = qw(TransientHTMLTree);

sub parse_file {
  my $me = shift;
  my $fn = shift;
  warn "unimplemented";
}

sub delete {
  my $me = shift;
  $me->{root} = undef;
  return 1;
}

sub as_HTML {
  my $me = shift;
  return $me->regen();
}

sub traverse {
  my $me = shift;
  my $cb = shift;
  $me->traverse2(sub {
    my $attribs = shift() or return; #or do { warn "no attribs"; return 0; };
    my $level = shift();
    my $ob = shift() or die;
    my $tagtmp = $attribs->{tag};
    substr($attribs->{tag}, 0, 1) = undef if(substr($attribs->{tag}, 0, 1) eq '/');
    $cb->(
      $ob,
      $attribs->{tag} eq $tagtmp, # true on start tag
      $level
    );
    $attribs->{tag} = $tagtmp;
  });
}

sub ignore_unknown {
  return 1;
}

sub warn {
  return 1;
}

sub implicit_tags {
  return 1;
}

1;

