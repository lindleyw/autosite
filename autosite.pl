#!/usr/bin/perl --

use File::Basename;

BEGIN { # push our directory onto include stack
  push @INC, dirname($0);
}

# AutoSite
# Copyright (c) 2002 wlindley.com, l.l.c.   http://www.wlindley.com
#
# Parse an HTML file, and all its referenced files, and 
# verify that all referenced files exist.  Also check the
# HEIGHT= and WIDTH= tags of <IMG> elements to verify their
# correct sizes.
#
# Written and maintained by William Lindley   wlindley@wlindley.com
#

use URI::URL;
use Cwd;

# use  autosite.pl [-c config_file.htm] mainfile.htm
# Can specify full pathnames to either config file or main HTML file.

use Getopt::Std;
BEGIN { getopt ('c:');  print "[[[$opt_c]]]\n";}

$scott = 1;   # TRUE if use Scott Walters' cool parser

if ($scott) { 
    use TransientBaby;
#    use TransientBits (template_file => 'site_template.htm');
    use TransientBits (template_file => $opt_c || 'site_template.htm');
#    use TransientHTMLTree;
    use TransientTreeBuilder;  # need to do this once it works
} else {
    use HTML::Element;
    use HTML::Parser;
    use HTML::TreeBuilder;
    
    sub HTML::TreeBuilder::comment { # CHEAT
	my $self = shift;
	my $pos = $self->{'_pos'};
	$pos = $self unless defined($pos);
	my $ele = HTML::Element->new('comment');
	$ele->push_content(shift);
	$pos->push_content($ele);
    }

=head2 $h->attrs()

Returns a list of attributes defined for the element.

=cut

    sub HTML::Element::attrs {
	# Return a list of all attributes defined for the element
	# wlindley@wlindley.com 1999-10-27
	my $self = shift;
	my @attrs = ();
	for (sort keys %$self) {
	    next if /^_/;
	    push @attrs, $_;
	}
	return @attrs;
    }
    
    sub HTML::Element::starttag
    {
	# Modified wlindley@wlindley.com 1999-10-27
	# to use Netscape style comments
	my $self = shift;
	my $name = $self->{'_tag'};
	return "<!--" if ($name eq 'comment');	# wl 1999-10-27
	my $tag = "<\U$name";
	for (sort keys %$self) {
	    next if /^_/;
	    my $val = $self->{$_};
	    if ($_ eq $val &&
		exists($boolean_attr{$name}) && $boolean_attr{$name} eq $_) {
		$tag .= " \U$_";
	    } else {
		if ($val !~ /^\d+$/) {
		    # count number of " compared to number of '
		    if (($val =~ tr/\"/\"/) > ($val =~ tr/\'/\'/)) {
			# use single quotes around the attribute value
		      HTML::Entities::encode_entities($val, "&'>");
			$val = qq('$val');
		    } else {
		      HTML::Entities::encode_entities($val, '&">');
			$val = qq{"$val"};
		    }
		}
		$tag .= qq{ \U$_\E=$val};
	    }
	}
	"$tag>";
    }

    sub HTML::Element::endtag
    {
	# Modified wlindley@wlindley.com 1999-10-27
	# to use Netscape style comments
	return "-->" if ($_[0]->{'_tag'} eq 'comment');	# wl 1999-10-27
	"</\U$_[0]->{'_tag'}>";
    }

    # We want the ending tags in place, so we have
    # removed from the below list:  p, th, tr, td, li, dt, dd .
    %HTML::Element::optionalEndTag = map { $_ => 1 } qw(option);
}

# -----------------------------

my %file_info;

sub file_info {
    # Set or get information about a file.
    my ($fname, $relation, $new_value) = @_;
    $fname =~ s{\\}{/}g;	# change DOS paths
    if (!defined $new_value) {
	# Return existing value if any
	return undef unless exists $file_info{$fname};	# File info not (yet) known
	return $file_info{$fname}{$relation};
    }
    $file_info{$fname}{$relation} = $new_value;
}

sub file_list {
    # Return a list of all files known
    return (sort keys %file_info);
}

sub unresolved {
    # Return a list of files which we must read to determine their contents.
#print "UNRESOLVED...\n";
#foreach (keys %file_info) {
#    print "   $_" . " " x (30 - length $_);
#    print "needed ", file_info($_, 'needed'), " needs ", file_info($_, 'needs'), "\n";
#}
#print "   ---\n";
    return grep {length($_) && (file_info($_,'needed') || file_info($_,'needs'))} (keys %file_info);
}

# -----------------------------

use File::Basename;
# fileparse_set_fstype("MSDOS");		# Normally inherits from $^O

sub normalize_path {
    # Accepts a file location (e.g., an HTML file), and a path relative to that file.
    # Returns a normalized path.  EXAMPLES:
    # ("P:members\index.htm", "../images/logo.gif") -> 'P:images/logo.gif'
    #	NOTE: the above is actually a relative path on drive P:
    # ("P:\web\members\index.htm", "../images/logo.gif") -> 'P:/web/images/logo.gif'

    my ($base_file, $rel_link) = @_;
    $base_file =~ tr[\\][/];		# use forward slashes
    ($base_file_name,$base_file_path,$base_file_suffix) = fileparse($base_file,'\..*');
    ($rel_link_name,$rel_link_path,$rel_link_suffix) = fileparse($rel_link,'\..*');
    $base_file_path =~ tr[\\][/];		# use forward slashes (again, after fileparse)
    $rel_link_name =~ tr[\\][/];
    # Append path, unless relative to current directory:
    $base_file_path .= $rel_link_path unless ($rel_link_path =~ m{^\.[\\\/]$});
    # Resolve '../' relative paths
    while ($base_file_path =~ s[\w+./\.\./][]g) {};
    # Concatenate path, name, and suffix
    $rel_link = $base_file_path . $rel_link_name . $rel_link_suffix;
    $rel_link =~ s[^./][];		# current directory is implied!
#    print "NAME = $base_file_name\nPATH = $base_file_path\nSUFFIX = $base_file_suffix\n";
#    print "-----> $rel_link\n";
    return $rel_link;
}

sub relative_path {
    my ($from_file, $to_file) = @_;
    my $relative_path='';
    
    $base_file =~ tr[\\][/];		# use forward slashes
    ($from_file_name,$from_file_path,$from_file_suffix) = fileparse($from_file,'\..*');
    ($to_file_name,  $to_file_path,  $to_file_suffix  ) = fileparse($to_file,  '\..*');
    $from_file_path =~ tr[\\][/];		# use forward slashes (again, after fileparse)
    $to_file_path   =~ tr[\\][/];
    $from_file_path = '' if ($from_file_path eq './'); # in document root directory? ignore
    $to_file_path = ''   if ($to_file_path   eq './');
    my @from_paths = split('/',$from_file_path);
    my @to_paths   = split('/',$to_file_path);

    #print "  ($from_file_path, $to_file_path)\n";
    #print "  from_paths: ", join(' ', @from_paths), "\n";
    #print "  to_paths:   ", join(' ', @to_paths), "\n";

    my $path_differs = 0;
    for (my $i = 0; $i < scalar @from_paths; $i++) {
	if ($path_differs) {
	  $from_paths[$i] = '..';	# Past a divergence, move back up out of 'from.'
	} else {
          if ($from_paths[$i] eq $to_paths[$i]) {
	    $from_paths[$i] = $to_paths[$i] = ''; # So far so good... no movement necessary
          } else {
	    $from_paths[$i] = '..';
	    $path_differs++;
          }
	}
    }
    $relative_path = join('/', grep($_ ne '', @from_paths), grep($_ ne '',@to_paths));
    $relative_path .= "/" if length($relative_path);
    $relative_path .= "$to_file_name$to_file_suffix";

    return $relative_path;

}

my $toc_true_location;

sub true_location {
    # Returns the location of a file in the site (possibly with a path
    # relative to the site's home), but relative to our cwd.
    my $fname = shift;
    return undef unless defined $fname;
    return '' unless length($fname);
    # print "@@@@@ true_location($fname) = ". normalize_path($toc_true_location, $fname) . "\n";
    return normalize_path($toc_true_location, $fname);
}

# -----------------------------

sub is_html {
    # Returns TRUE if a file is HTML.
    my $fname = shift;

    if (exists $file_info{$fname} && exists $file_info{$fname}{'is_html'}) {
	return $file_info{$fname}{'is_html'};
    }

    my $true_fname = true_location($fname);
    return 0 unless -e $true_fname;
    return 0 unless -T $true_fname;
    open IS_HTML_FILE, $true_fname;
    read(IS_HTML_FILE, my $header, 1024);	# Read up to 1024 bytes
    close IS_HTML_FILE;
    # return TRUE if it looks like we have a start tag.  Also save the value.
    return ($file_info{$fname}{'is_html'} = $header =~ /<HTML/i);
}

sub is_local {
    # Returns TRUE if a file is local (e.g., not "http://...")
    my $url = shift;
    my $is_remote = ($url =~ /\:/);
    return !$is_remote;
}

sub image_size {
    # Returns width, height of image
    my $fname = shift;
    if (exists $file_info{$fname} && exists $file_info{$fname}{'width'}) {
	return ($file_info{$fname}{'width'},$file_info{$fname}{'height'});
    }
    my $true_fname = true_location($fname);
    if (-e $true_fname) {
	open IMAGE, $true_fname;
	my $bytesread = read(IMAGE, my $gif_header, 12);
	close IMAGE;
	return undef unless ($bytesread == 12);
	my ($id, $width, $height) = unpack ("a6vv",$gif_header);
	return undef unless ($id eq "GIF89a");
	($file_info{$fname}{'width'},$file_info{$fname}{'height'}) = ($width, $height);
	return ($width, $height);
    }
    return undef;
}

# -----------------------------

# The root document (specified on the command-line) will be the 'toc' for
# the entire collection of documents.  This is useful for the site's home-page.
# Documents containing "child" links will "adopt" their children, and any child's
# "parent" link will automatically be updated to its adoptive parent.

# Save these relations:
my %tracked_relation = map { $_ => 1 } qw(child extra chapter);	

# 'next' node (and reverse, 'prev') created from child:
my %create_relation = ('child' => 'next');     

# "extra" is like "child" but is exempt from the next/prev navigation.
my %reverse_relation = (
    'prev' => 'next', 'next' => 'prev',
    'child' => 'parent', 'parent' => 'child',
    'extra' => 'parent'
    );

# Chapters of various types are considered as children for navigation.
my %chapter_relation = (
    'chapter' => 'child',
    'glossary' => 'child',
    'appendix'=> 'child'
);

# Meta-information to save.  Maps <META NAME="navtitle" CONTENT="foo"> to
# file_info( filename, 'navtitle', 'foo')
my %saved_meta = (
		  'copyright' => 'copyright',
		  'navtitle' => 'navtitle',
		  'description' => 'meta_desc',
		  'author' => 'author',
		  'distribution' => 'distribution',
		  'keywords' => 'keywords',
		  'rating' => 'rating',
		  );

# 
my %changes = ('href_alt' => 'title');

# These tags, when CLASS="autosite" ID="function|param|param" will
# cause a subroutine call.
my %autosite_tag = ('ins' => 1, 'span' => 1, 'div' => 1);

# Maintain list of Chapters for navigation bar.
# If the site contains <A HREF="xxx" REL="chapter"> these are kept in the
#   chapter list regardless of their location
# Otherwise, all the children of the root node are assumed to be chapters.
my $site_explicit_chapters = 0; # TRUE if explicit chapters
my @chapters; # files which are chapters

# -----------------------------

#use Date::Manip qw(ParseDate UnixDate);
#$TZ = "PST";		# because MSDOS doesn't have a TZ variable

my @tag_stack;

sub process_entry {
    my ($node, $startflag, $depth) = @_; # startflag e.g., TRUE for <A>, FALSE for </A>

    my $tag;
    
    if ($scott) {
	if ($node->tag() eq 'lit') { # literal text
	    if ($grab_header) {	# save text of this entity
		$header .= $node->attr('text');
	    }
	    return 1;
	}
    } else {
        # ------ HTML::TreeBuilder way of doing things
	unless (ref($node)) {     
	    if ($grab_header) {	# save text of this entity
		$header .= $node;
	    }
	    return 1;
	}
    }

    $tag = $node->tag();
    $tag_stack[$depth] = $node;

# print "<$tag>  ($startflag, $depth)\n";
    if ($tag eq 'title' && $startflag) {
	file_info($base, 'title_ref', $node);			# Save reference to TITLE element
    }

    if (($tag eq $header_type) && ($grab_header == $depth) && ($startflag == 0)) {
	# <TITLE> gets saved if defined.  Override with <H1> if present.
	# At end of <H1> save its text as the file's <TITLE>.
	$header =~ s/\s+$//;				# Remove trailing spaces
	file_info($base,'title',$header);		# Save title in our database
#print " Setting title of $base --> [$header]\n";
	$grab_header = 0;
	if ($tag ne 'title') {				# Override <TITLE> with <H1>
	    my $title_ref = file_info($base, 'title_ref');	# Reference to <TITLE> entity
	    if (defined $title_ref && ref ($title_ref)) {
		$title_ref->delete_content();		# Replace existing content
		$title_ref->push_content($header);
	    }
	}
    }

    # Find current title and possibly override
    if (($tag eq 'title') && $startflag) {	# Find current title
    	unless (file_info($base,'title')) {	# After first reading, use title found below.
	    $grab_header = $depth;
	    $header_type = $tag;
	    $header = '';
#print "Finding <TITLE>\n";
	}
    } elsif (($tag =~ /^h[1-4]$/) && $startflag) {	# Override with first of H1-H4
    	unless (file_info($base, 'title_override')) {
	    file_info($base, 'title_override', 1);
	    $grab_header = $depth;
	    $header_type = $tag;
	    $header = '';
#print "Overriding <TITLE> with <$tag>\n";
	}
    }

    if (($tag eq 'br') && $grab_header) {		# line break in header counts as a space
	$header .= ' ';
    }

    if ($tag eq 'meta') {
	my $meta_name = lc($node->attr('name'));
	if ($saved_meta{$meta_name}) { # process this meta tag
	    my $content = $node->attr('content');
	    # Begin value with asterisk to inherit from TOC, if it has that value
	    if ($content =~ /^\*/) {
		my $new_content = file_info(file_info('/', 'toc'),$saved_meta{$meta_name});
		$content = '*' . $new_content if $new_content;
		$node->attr('content', $content);
	    }
	    # Store the value
	    file_info($base, $saved_meta{$meta_name}, $content);
	}
	if ($meta_name =~ /^generator$/i) { # automatically update Generator
	    $node->attr('content', "AutoSite 0.4");
	}
    }

    if ($tag eq 'a' && $startflag) {
	my $link = $node->attr('href');
	if (is_local($link)) {
	    $link =~ s/#.*$//;				# Remove fragment part of link
	    my $link = normalize_path($base,$link);
#print "LINK TO: $link ... is_html=", is_html($link), "\n";
	    if (is_html($link)) {
		# Count links to this page
		file_info($link, 'links_to', file_info($link, 'links_to')+1);
	    }

	    my $relation = $node->attr('rel');
	    if (defined $relation) {
		if ($tracked_relation{$relation} && is_html($link)) {

		    # Chapters are automatically all children of the root node,
		    # or only those explicitly given (if at least one is explicit).
		    if ($chapter_relation{$relation}) {
			if (!$site_explicit_chapters) { 
			    @chapters = (); # convert to explicit; discard previous implicits
			    $site_explicit_chapters = 1;
			}
			push @chapters, $link;
			# note: modifying $relation here must NOT change file!
			file_info($base, 'chapter', $relation); # Save relation as defined
			$relation = $chapter_relation{$relation};
		    } elsif ($relation eq 'child' && !$site_explicit_chapters &&
			     $base eq file_info('/', 'toc')) {
			push @chapters, $link; # implicit chapters
		    }

		    # Remember child relations.
		    my @children = split('\|', file_info($base, $relation));
		    my %links = map { $_ => 1 } @children;
#print " ($base,$relation) = ", file_info($base,$relation), "\n";;
		    # Set reverse relation in this node
		    if (defined $reverse_relation{$relation}) {
			file_info($link, $reverse_relation{$relation}, $base);
			#print "\t*$link has $reverse_relation{$relation} $base\n";
			#$node->attr('rel',$reverse_relation{$relation});
		    }

		    # Append link to list of this relation.  (A parent can have several children.)
		    unless ($links{$link}) {
			if (defined $create_relation{$relation}) {
			    # First and last children have no previous and next, respectively.
			    file_info($link, $create_relation{$relation}, "#")
				unless file_info($link, $create_relation{$relation});
			    file_info($link, $reverse_relation{$create_relation{$relation}}, "#")
				unless file_info($link, $reverse_relation{$create_relation{$relation}});
			    # Last's next is us; our previous is whoever was formerly last.
			    if (scalar @children) {
				file_info($children[-1], $create_relation{$relation}, $link);
				#print "\t$children[-1] has $create_relation{$relation} = ",file_info($children[-1], $create_relation{$relation}),"\n";
				file_info($link, $reverse_relation{$create_relation{$relation}}, $children[-1]);
				#print "\t$link has $reverse_relation{$create_relation{$relation}} = ",file_info($link, $reverse_relation{$create_relation{$relation}}),"\n";
			    }
			}
			file_info($base,$relation, join('|', @children, $link));
			#print "  $base has $relation ", file_info($base,$relation),"\n";
			file_info($base,'head', $children[0]);	# remember firstborn
			#print "  $base has head = $children[0]\n";
		    }
		} elsif (file_info($base, $relation)) {
		    # This is a relation we're creating; use a relative path.
		    my $new_href = file_info($base, $relation);
		    # If it's just a fragment, don't process it as a path.
		    $new_href = relative_path($base,$new_href) unless $new_href =~ /^#/;
		    $node->attr('href', $new_href);
#print "\tSetting HREF of $relation to $new_href\n";
		} elsif ($relation eq 'toc' || $relation eq 'contents') {
		    $node->attr('href', relative_path($base,file_info('/','toc')));
		} else {
		    #print "\tIgnoring $relation in $base\n";
		}
	    }

	    $link = normalize_path($base,$node->attr('href'));		# May have been changed above.
#print " >>> $link\n";
	    if ($link eq '#') {
		# $node->attr('alt','');			# Erase old alt text
	    } elsif (is_html($link)) {
		# Set the ALT text to the destination's title
		my $alt_text = file_info($link,$changes{'href_alt'});
		if (defined $alt_text) {
		    # $node->attr('alt',$alt_text);
#  print " >>>>>> Resolved $link ... [$alt_text]\n";
		} else {
		    # Remember that we must read this file later to resolve the dependency.
# print " >>>>>> Unresolved [$link] in [$base] ... must read it later.\n";
		    file_info($link,'needed',1);
		    file_info($base,'needs',1);
		}
	    }
	}
    }
    
    # Not yet handled.
#    if ($tag eq 'link') {
#	if ($node->attr('rel') eq 'consistency_config') {
#	    # print "CONFIG FILE IS: ",normalize_path($base,$node->attr('href')),"\n";
#	}
#    }
    
    if ($tag eq 'img') {
	my $preview = $node->attr('src');
	my $img_src_rel_path;
	if (is_local($preview)) {
	    $img_src_rel_path = normalize_path($base,$preview);
	    if ($img_src_rel_path =~ /\.gif$/) {
		my ($file_width, $file_height) = image_size($img_src_rel_path);
		if (!defined $file_width) {
		    print STDERR "In $base : Image $img_src_rel_path not found\n";
		    return;
		}
		my $html_width = $node->attr('width');
		my $html_height= $node->attr('height');
		if (($file_width != $html_width || $file_height != $html_height) && ($file_width > 1)) {
		    print STDERR "In $base : Image size of $img_src_rel_path should be $file_width x $file_height\n";
		    # Set the correct values:
		    $node->attr('width', $file_width);
		    $node->attr('height', $file_height);
		}
	    }
	}

#    print "  -> Node: [", $node->tag(), "] node's parent: [", $node->parent()->tag(), "]\n";
	if ($node->parent()->tag() eq 'a') {
	    my $link = $node->parent()->attr('href');
#    print "(node's parent is <A HREF='$link'>)\n";
	    my $href_rel_path = normalize_path($base, $link);
	    my $alt_text = '';
	    
	    if ($link ne '#' && length($link) ) {		# '#' alone means no link
		$alt_text = file_info($href_rel_path,$changes{'href_alt'});
		if (defined $alt_text) {
		    $node->attr('alt',$alt_text);
		} elsif (is_html($href_rel_path)) {
		    # Remember that we must read this file later to resolve the dependency.
#     print "Unresolved '$href_rel_path' ... must read it later.\n";
		    file_info($href_rel_path,'needed',1);
		    file_info($base,'needs',1);
		}
		$preview =~ s/(left|right|up|down)(no)?\.gif/\1.gif/;
	    } else {
		$preview =~ s/(left|right|up|down)(no)?\.gif/\1no.gif/;
	    }

	    $node->parent()->attr('rel','parent') if ($preview =~ /\bnav\/up(no)?\.gif/);
	    $node->parent()->attr('rel','head')   if ($preview =~ /\bnav\/down(no)?\.gif/);
	    $node->parent()->attr('rel','prev')   if ($preview =~ /\bnav\/left(no)?\.gif/);
	    $node->parent()->attr('rel','next')   if ($preview =~ /\bnav\/right(no)?\.gif/);

	    $node->attr('src', $preview);
	    $node->attr('alt', $alt_text);
	    #print "<A> with HREF= $href_rel_path and <IMG SRC>= $img_src_rel_path\n  set ALT = $alt_text\n";
	}
    }
if ($scott) {
    # <DIV CLASS="autosite">...</DIV> have their content removed and replaced
    # with automatic material.
    if ($autosite_tag{$tag} && $startflag && $node->attr('class') =~ /^autosite/i) {
	#$node->delete_content();
	$node->set_child(undef); # orphan our children
	# now remove everything until end of encompassing tag
	while ($node->get_next()->tag() ne "/$tag") {
	    # unlink next element in doubly linked list
	    $node->set_next($node->get_next()->get_next()); 
	    $node->get_next()->set_previous($node);
	}
        # following assumes ID tag contains name of routine which generates output
	# this should be probably changed to something less prone to crash. ~~~

	my @args = split /\./, $node->attr('id'); # subroutine name and all args
	my $to_call = shift @args; # sub given first

	my $new_text = $to_call->(@args) if $to_call;   # soft reference
	#my $new_tag = TransientHTMLTreeNode->new();
	#$new_tag->set_attribs({tag => 'lit', text => $new_text});
	$node->push_content($new_text);
    }
}
    return 1;
}

sub chapter_type {
    # returns the chapter type of a document, or undef if it is not a chapter
    my $node = shift;
    return "toc" if ($node eq file_info('/','toc')); # table of contents
    if ($site_explicit_chapters) {
	return file_info($node, 'chapter'); # relation as defined in toc
    } else {
	foreach (@chapters) {
	    return 'chapter' if ($_ eq $node); # implicit chapter
	}
    }
    return undef;
}

#-------------------

sub webprint {
    # using 'sprintf' from HTML says &main::sprintf undefined? -- wl
    my ($string, @args) = @_;
    return sprintf($string, @args);
}

sub linkify {
    my ($link, $text, $class, $id, $style) = @_;
    $text = "(no title)" unless $text;
    $class = " CLASS=\"$class\"" if $class;
    $id    = " ID=\"$id\""       if $id;
    $style = " STYLE=\"$style \"" if $style;
    return "<A HREF=\"$link\"$class$id$style>$text</A>";
}

sub full_contents_of {
    my ($node, $level, $style) = @_;
    my ($my_html, $pre_html, $post_html, $my_pre_html, $my_post_html);
    my $id = ($node eq $base) ? 'current-nav' : '';  # current-nav ID so we can set <STYLE>
    my $title = file_info($node, 'navtitle');  # Default to navigation title
    if (($style =~ /\bfull\b/i) || length($title) == 0) { # wants full title, or no navigation title
	$title = file_info($node, 'title') ;
    }
    my $link_html = linkify(relative_path($base, $node), $title, chapter_type($node),$id);

    if ($style =~ /\bul\b/i) {
	$my_html = "$link_html";
	$pre_html = "<UL>\n";
	$my_html = "<LI>$link_html\n"; # omit </LI>
	$post_html = "</UL>\n";
	if ($level == 0) {
	    $my_html = $link_html;  # Don't put top level in a list
	}
    } elsif ($style =~ /\bol\b(?:-(\w*))?/i) {
	my $levels = $1 x 10; # repeat
	my $ol_type = ' TYPE="' . substr($levels,$level,1) . '"'; # for next level
	$my_html = "$link_html";
	$pre_html = "<OL$ol_type>\n";
	$my_html = "<LI>$link_html</LI>\n";
	$post_html = "</OL>\n";
	if ($level == 0) {
	    $my_html = $link_html;  # Don't put top level in a list
# possibly useful if you wanted the Root in the same type of content:
#	    $my_pre_html = $pre_html; $my_post_html = $post_html;
	}
    } else {
	$my_html = '&nbsp' x ($level * 2) . $link_html . "<BR>\n";
    }

    my $html = '';
    $html = $my_pre_html;
    my @children = split('\|', file_info($node, 'child'));
    if (scalar @children) {
	$html .= "$my_html$pre_html";
	foreach (@children) {
	    if (file_info($_, 'needed')) {    # We depend on all files
		$html = '~~~unresolved~~~';   # so if there is even one file not yet read in,
		break;                        # stop now and flag the calling file with Needs.
	    }
	    $html .= full_contents_of($_, $level + 1, $style);
	}
	$html .= $post_html;
    } else {
	$html .= $my_html;
    }
    $html .= $my_post_html;
    return $html;
}

sub full_contents {
    # Return html containing indented tree with contents of entire site
    # in HTML:
    #    <span class="autosite" id="full_contents.ul></span>
    # or <span class="autosite" id="full_contents.ol-1Aia></span>
    # 'ul' means use Unordered list; 'ol' means ordered list;
    # omit for indented with spaces.
    my $root = file_info('/', 'toc');
    my $level = 0;
    my $html = '';
    my $style = shift;

    my $content_table = full_contents_of($root, $level, $style);
    if ($content_table =~ '~~~unresolved~~~') {
	file_info($base, 'needs', 1); # Build this page only after all other files read in.
    } else {
	$html .= $content_table;
    }
    return $html;
}

sub sidenav_element {
    my ($node, $level, $style) = @_;
    my $link_prefix;
    my $link_suffix = "<BR>\n";

    unless (file_info($node, 'seen')) { # flag forward reference
	file_info($base, 'needs', 1);
    }
    my $node_title = file_info($node, 'navtitle'); # short title for navigation bar
    # default to regular title:
    $node_title = file_info($node, 'title') unless $node_title; 
    # Compute path from containing file to this node and create link
    my $nav_class = 'sidenav';
    my $nav_id = ($node eq $base) ? 'current-nav' : '';  # current-nav ID for use with <STYLE>
    my $nav_style;
    if ($style =~ /\bnbsp\b/) { # change spaces in title to non-breaking
	$node_title =~ s/\s+/&nbsp;/g;
    }
    if ($style =~ /\bindent(\d*)/) { # use text-indent property
	my $multiple = $1 || 7; # specified or default to 0.7 em
	$nav_style .= "margin-left: " . $level * $multiple / 10 . "em;";
    } else {
	$link_prefix = "&nbsp;&nbsp;" x $level;
    }
    my $link_html = linkify(relative_path($base, $node), $node_title,
			    $nav_class, $nav_id, $nav_style);
    return "$link_prefix$link_html$link_suffix";
}

sub sidenav {
    # create the sidebar navigation
    my $style = shift;

    my $adam = file_info("/","toc"); # name of the file in the first generation
    my $ancestor; # the child off '/' who is our progenitor
    my $parent = $base;
    my @begats;
    my @use_chapters = ($adam, @chapters);
    my $return_html;

    # trace ancestry back to the first generation (TOC)
    if ($parent eq $adam) {
	$ancestor = $base; # We are Adam, the TOC.
	@use_chapters = @saved_chapters;  # The array from last iteration
 	$return_html .= sidenav_element($base, 0, $style);
    } else {
	while (($parent ne $adam) && length($parent)) {
	    $ancestor = $parent; 
	    unshift @begats, $parent;
	    $parent = file_info($parent,'parent');
	}
    }

    $parent = scalar(@begats) > 1 ? $begats[-2] : ''; # Parent of nodes at least grandkids of TOC
    foreach (@use_chapters) { # List all chapters (instead of all children of the TOC)
	if ($_ eq $ancestor) { # insert our family tree here
	    my $indent=0;
	    my $self_listed=0;
	    if (scalar @begats == 1) { # our siblings are the chapters - only show children under us
		$return_html .= sidenav_element($_, $indent++, $style);
		if ($style =~ /\bchild\b/i) {
		    foreach my $node (split('\|', file_info($base, 'child'))) {
			$return_html .= sidenav_element($node, $indent + 1, $style);
		    }
		}
	    	next;
	    }
	    foreach my $node (@begats) { # includes our parent and us.
	    	next if (($node eq $base) && $self_listed);
		$return_html .= sidenav_element($node, $indent++, $style);
		# List our siblings under our parent
		if ($node eq $parent) {
		    foreach my $node (split('\|', file_info($parent, 'child'))) {
			$return_html .= sidenav_element($node, $indent, $style);
			next unless ($node eq $base);
			$self_listed++;
			# List our children under us
			if ($style =~ /\bchild\b/i) {
			    foreach my $node (split('\|', file_info($base, 'child'))) {
				$return_html .= sidenav_element($node, $indent + 1, $style);
			    }
			}
		    }
		}
	    }
	} else { # Chapter, but not our ancestor
	    $return_html .= sidenav_element($_, 0, $style);
	}
    }
    return $return_html;
}

sub makerelative {
    # This calls a function, takes the HTML it returns, and rewrites
    # the links in it to be relative to the current page instead of the
    # document root.
    my $func = shift;
    my $text = $func->();
#print "BEFORE: [[ $text ]]\n";
    $text =~ s/(href|src)\s*=\s*"([^"]+)"/"$1=\"" . relative_path($base,$2) . '"'/sgie;
#print "AFTER: [[ $text ]]\n";
    return $text;
}


#-------------------
#
# Main program
#
#-------------------

print "AutoSite Version 0.4  05 June 2002  (c) Copyright 2002 wlindley.com, l.l.c.\n";

use File::DosGlob 'glob';  # override CORE::glob

undef $/;

@basefiles = glob $ARGV[0];

$toc_true_location = $basefiles[0]; # First file is actual base, possibly with path

foreach $base (@basefiles) {
    unless (defined $base) {
	die "Must specify input file.\n";
    }
    $base = relative_path($toc_true_location, $base); # use file's relative location in site
    file_info("/","toc",$base) unless file_info("/","toc"); # Set collection's toc
    file_info($base,'needed',1);	# Set "Needed by other files" flag
}

while (scalar (@files = unresolved())) {
    # print "Unresolved: ", join(',', @files), "\n";

    foreach $base (@files) {

	# Find "true" path in our filesystem (as opposed to site's relative structure)
	my $true_base = true_location($base);

	# For the file under consideration, clear its "Needed by others" and "Needs others"
	# flags.  These may be set during traversal.
	file_info($base,'needed',0);
	file_info($base,'needs',0);
	
	unless (-e $true_base) {
	    die "Cannot open input file '$base'\n";
	}
	unless (-T $true_base) {
	    die "$base is not a text file.\n";
	}
	
	print "Reading $base [$true_base]\n";
	file_info($base,'seen',1);	# Remember we have seen this file at least once.

	if ($base eq file_info('/', 'toc')) {
	    # clear chapter list - we could process this node several times.
	    @saved_chapters = @chapters;
	    @chapters = ();
	}

	open FILE, $true_base;
	$text = <FILE>;
	close FILE;

	if ($scott) {
	    $text =~ s/<![a-zA-Z]+[^>]*>//;  # Remove offensive XML-ish tag foolishness
	    $h = new TransientTreeBuilder; 
	} else {
	    $h = new HTML::TreeBuilder;
	}

	$h->ignore_unknown(0);
	$h->warn(1);
	$h->implicit_tags(0);
	$h->parse($text);
	
	$h->traverse(\&process_entry);
	
	if (file_info($base,'needs') == 0) {
	    # All dependencies resovled.  Safe to write it out.
	    my $new_text = $h->as_HTML();
	    # for some reason, as_HTML emits multiple HTML start and end tags?
	    #$new_text =~ s[(<HTML>\s*){2,}][<HTML>]gs;	
	    #$new_text =~ s[(</HTML>\s*){2,}][</HTML>]gs;	# likewise
	    $new_text =~ s[<HTML>.*<HTML>][<HTML>]gs;		# Get rid of multiple HTML begins...
	    $new_text =~ s[(</HTML>\s*)+][</HTML>]gs;		# ...and ends
	    $new_text =~ s[(<[a-z]+)\s][\1\n]gi; # "<A HREF" becomes "<A\nHREF"
	    $new_text =~ s[\s</A][</A]gis;	# remove spaces before end anchors

	    print "WRITING: $base [$true_base]\n";
	    open FILE, ">$true_base";
	    print FILE $new_text;
	    print FILE "\n";
	    close FILE;
	} else {
	    file_info($base,'needed',1);	# Show we must process it again
	    # print "     Flagged for reprocess: $base\n";
	}
	$h->delete();
    }
}

print "Chapters:\n";
foreach (@chapters) {
    print "  $_ " . (file_info($_, 'chapter') || '(implicit)') . "\n";
}



__END__;
