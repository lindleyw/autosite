#!/usr/bin/perl --

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
# You may distribute this code under the GNU public license
#
# THIS SOFTWARE IS PROVIDED "AS-IS" WITHOUT WARRANTY OF ANY KIND.
#
# $Id: autosite.pl,v 0.0 1980/01/01 14:22:44 bill Exp $
#

my $debug = 0;
my $warnings = 0;

use File::Basename;

BEGIN {
  push @INC, dirname($0); # So we can find our own modules

  # CVS puts the revision here
  ($version) = '$Revision: 0.7 $ ' =~ /([\d\.]+)/;
}

use URI::URL;
use Cwd;

# use  autosite.pl [-c config_file.htm] mainfile.htm
# Can specify full pathnames to either config file or main HTML file.

use Getopt::Std;
BEGIN {
    # Currently the only command line argument is -c <template_file>
    getopt ('c:');
}

use TransientBaby;
use TransientBits (template_file => $opt_c || 'site_template.html');
use TransientTreeBuilder;

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
    return grep {
	length($_) && 
	    (file_info($_,'needed') || file_info($_,'needs'))
	} (keys %file_info);
}

# -----------------------------

# fileparse_set_fstype("MSDOS");		# Normally inherits from $^O

sub normalize_path {
    # INPUTS:
    #  * file location (e.g., an HTML file)
    #  * a path relative to that file.
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
    # Basically the inverse of normalize_path.
    # Accepts two paths, and returns a relative path
    # from the first to the second.
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
	  $from_paths[$i] = '..';
	  # Past a divergence, move back up out of 'from.'
	} else {
          if ($from_paths[$i] eq $to_paths[$i]) {
	    $from_paths[$i] = $to_paths[$i] = ''; 
	    # So far so good... no movement necessary
          } else {
	    $from_paths[$i] = '..';
	    $path_differs++;
          }
	}
    }
    $relative_path = join('/', grep($_ ne '', @from_paths), 
			  grep($_ ne '',@to_paths));
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
    return normalize_path($toc_true_location, $fname);
}

# -----------------------------

sub is_local {
    # Returns TRUE if a file is local (e.g., not "http://...")
    my $url = shift;
    my $is_remote = ($url =~ /\:/);
    return !$is_remote;
}

sub is_html {
    # Returns TRUE if a file is HTML.
    my $fname = shift;

    if (exists $file_info{$fname} && exists $file_info{$fname}{'is_html'}) {
	return $file_info{$fname}{'is_html'};
    }

    return 0 unless is_local($fname);
    my $true_fname = true_location($fname);
    return 0 unless -e $true_fname;
    return 0 unless -T $true_fname;
    open IS_HTML_FILE, $true_fname;
    read(IS_HTML_FILE, my $header, 1024); # Assumes leading <!...> less than 1K
    close IS_HTML_FILE;
    # return TRUE if it looks like we have a start tag.  Also save the value.
    return ($file_info{$fname}{'is_html'} = $header =~ /<HTML/i);
}

# ---
# from -- http://www.bloodyeck.com/wwwis/wwwis
# jpegsize : gets the width and height (in pixels) of a jpeg file
# Andrew Tong, werdna@ugcs.caltech.edu           February 14, 1995
# modified slightly by alex@ed.ac.uk
sub jpegsize {
  my($done)=0;
  my($c1,$c2,$ch,$s,$length, $dummy)=(0,0,0,0,0,0);
  my($a,$b,$c,$d);

  if(read(IMAGE, $c1, 1)	&&
     read(IMAGE, $c2, 1)	&&
     ord($c1) == 0xFF		&&
     ord($c2) == 0xD8		){
    while (ord($ch) != 0xDA && !$done) {
      # Find next marker (JPEG markers begin with 0xFF)
      # This can hang the program!!
      while (ord($ch) != 0xFF) { return(0,0) unless read(IMAGE, $ch, 1); }
      # JPEG markers can be padded with unlimited 0xFF's
      while (ord($ch) == 0xFF) { return(0,0) unless read(IMAGE, $ch, 1); }
      # Now, $ch contains the value of the marker.
      if ((ord($ch) >= 0xC0) && (ord($ch) <= 0xC3)) {
	return(0,0) unless read (IMAGE, $dummy, 3);
	return(0,0) unless read(IMAGE, $s, 4);
	($a,$b,$c,$d)=unpack("C"x4,$s);
	return ($c<<8|$d, $a<<8|$b );
      } else {
	# We **MUST** skip variables, since FF's within variable names are
	# NOT valid JPEG markers
	return(0,0) unless read (IMAGE, $s, 2);
	($c1, $c2) = unpack("C"x2,$s);
	$length = $c1<<8|$c2;
	last if (!defined($length) || $length < 2);
	read(IMAGE, $dummy, $length-2);
      }
    }
  }
  return (0,0);
}

sub gifsize {
  my($type,$a,$b,$c,$d,$s)=(0,0,0,0,0,0);

  if(read(IMAGE, $type, 6)	&&
     $type =~ /GIF8[7,9]a/	&&
     read(IMAGE, $s, 4) == 4	){
    ($a,$b,$c,$d)=unpack("C"x4,$s);
    return ($b<<8|$a,$d<<8|$c);
  }
  return (0,0);
}

#-----

sub image_size {
    # Returns width, height of image
    my $fname = shift;
    my @size = (file_info($fname,'width'),file_info($fname,'height'));
    return @size if ($size[0] && $size[1]); # already found
#    if (exists $file_info{$fname} && exists $file_info{$fname}{'width'}) {
#	return ($file_info{$fname}{'width'},$file_info{$fname}{'height'});
#    }
    my $true_fname = true_location($fname);
    if (-e $true_fname) {
	open IMAGE, $true_fname;
	binmode IMAGE;
	@size = jpegsize() if $fname =~ /\.jpe?g$/i;
	@size = gifsize() if $fname =~ /\.gif$/i;
	close IMAGE;
	file_info($fname,'width',$size[0]);
	file_info($fname,'height',$size[1]);
	return @size;
    } else {
	print STDERR "Image not found: $true_fname\n";
    }
    return undef;
}

# -----------------------------

# The root document (specified on the command-line) will be the 'toc' for
# the entire collection of documents.  This is useful for the site's home-page.
# Documents containing "child" links will "adopt" their children, and any
# child's "parent" link will automatically be updated to its adoptive parent.

# Save these relations:
my %tracked_relation = ('child' => 'child', 
			'chapter' => 'child',
			'section' => 'child',
			'extra' => 'extra',
			'subsection' => 'extra',
			);

# 'next' node (and reverse, 'prev') created from child.
# Entries here must appear in tracked_relation{} to be active.
my %create_relation = ('child' => 'next', 'section' => 'next');

# "extra" and "subsection" are like "child" yet exempt from the next/prev navigation.
my %reverse_relation = (
			'prev' => 'next', 'next' => 'prev',
			'child' => 'parent', 'parent' => 'child',
			'section' => 'parent',
			'extra' => 'parent',
			'subsection' => 'parent',
			);

# Chapters are main sections and considered as children for navigation.
my %chapter_relation = (
			'chapter' => 'child',
			'glossary' => 'child',
			'appendix'=> 'child'
			);

# maps navigation images to href relations
my %image_relations = (
		       up => 'parent',
		       down => 'head',
		       left => 'prev',
		       right => 'next', 
		       glossary => 'glossary',
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

# These tags, with CLASS="autosite" ID="function|param|param" will
# cause a subroutine call.
my %autosite_tag = ('ins' => 1, 'span' => 1, 'div' => 1);

# Create <LINK REL="---" HREF="---"> for HTML 4.0 capable browsers.
my %link_relations = (
		      start     => '#/toc*',   # Root node / Main page
		      parent    => 'parent',
		      up        => '#parent',
		      first     => '^head',     # Our eldest sibling
		      prev      => 'prev',      # Our older sibling
		      next      => 'next',      # Our younger sibling
		      last      => '^tail',     # Our youngest sibling
		      contents  => '/toc*',
		      chapter   => '/child',
		      section   => 'child*',
		      appendix  => '/appendix',
		      glossary  => '/glossary!',
		      index     => '/index!',    # Site map
		      help      => '/help!',
		      search    => '/search!',
		      copyright => '/copyright!',
		      
		      # NOTES:
		      #  '/'  refers to root node's info
		      #  '!'  means the value will be taken from the root node, not computed.
		      #  '^'  refers to parent's info
		      #  '*'  will suppress this entry for the root node
		      #  '#'  recognizes the link as navigation on input but does not generate.
		      #  '--' suggests the <link> be untouched during processing
		      );

# Maintain list of Chapters for navigation bar.
# If the site contains <A HREF="xxx" REL="chapter"> these are kept in the
#   chapter list regardless of their location
# Otherwise, all the children of the root node are assumed to be chapters.
my $site_explicit_chapters = 0; # TRUE if explicit chapters
my @chapters; # files which are chapters

my %stylesheets;

# -----------------------------

#use Date::Manip qw(ParseDate UnixDate);
#$TZ = "PST";		# because MSDOS doesn't have a TZ variable

sub is_root {
    # returns TRUE if the document is the root node
    my $node = shift;
    return ($node eq file_info('/','toc')); # table of contents
}

sub chapter_type {
    # returns the chapter type of a document, or undef if it is not a chapter
    my $node = shift;
    return "toc" if (is_root($node)); # table of contents
    if ($site_explicit_chapters) {
	return file_info($node, 'chapter'); # relation as defined in toc
    } else {
	foreach (@chapters) {
	    return 'chapter' if ($_ eq $node); # implicit chapter
	}
    }
    return undef;
}

# -----------------------------
#
# used by below process_entry which is callback in traverse()
#
# -----------------------------

my $autotext = 0;

sub process_quote {
    my ($node, $startflag, $depth) = @_;

    if ($startflag) {
	my $link = $node->attr('cite');
	if (defined $link) {
	    $link =~ s/#.*$//;				# Remove fragment part of link
	    if (length($link)) {  # if it's an internal citation, it will be blank now.
		$link = normalize_path($base,$link) if (is_local($link));
		# do something here? ~~~~~~~~~~~~~~
	    }
	}
    }

    return 1;
}

sub process_meta {
    my ($node, $startflag, $depth) = @_;

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
	$node->attr('content', "AutoSite $version");
    }
    return 1;
}

sub process_a {
    my ($node, $startflag, $depth) = @_;

    return 1 unless $startflag;

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
	    if ($tracked_relation{$relation} && is_html($link) && !$autotext) {
		my %chapters = map{ $_, 1} @chapters;
		# Chapters are automatically all children of the root node,
		# or only those explicitly given (if at least one is explicit).
		# Also excludes links created automatically (as in navigation bars).
		if ($chapter_relation{$relation}) {
		    if (!$site_explicit_chapters) { 
			@chapters = (); # convert to explicit; discard previous implicits
			$site_explicit_chapters = 1;
			print "*** EXPLICIT CHAPTERS ***\n" if $warnings;
		    }
		    push @chapters, $link unless ($chapters{$link});
		    # note: modifying $relation here must NOT change file!
		    file_info($base, 'chapter', $relation); # Save relation as defined
		    $relation = $chapter_relation{$relation};
		} elsif ($create_relation{$relation} && !$site_explicit_chapters &&
			 is_root($base)) {
		    push @chapters, $link unless ($chapters{$link}); # implicit chapters
		}

		# Remember child and other relations.
		$relation = $tracked_relation{$relation};
		my @children = @{file_info($base, $relation)};
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
			    #print "\t$children[-1] has $create_relation{$relation} = ",
			    #file_info($children[-1], $create_relation{$relation}),"\n";
			    file_info($link, $reverse_relation{$create_relation{$relation}}, $children[-1]);
			    #print "\t$link has $reverse_relation{$create_relation{$relation}} = ",
			    #file_info($link, $reverse_relation{$create_relation{$relation}}),"\n";
			}
		    }
		    file_info($base, $relation, [@children, $link]);
		    #print "  $base has $relation ", file_info($base,$relation),"\n";
		    file_info($base,'head', $children[0]);	# remember firstborn
		    file_info($base,'tail', $link);             # and lastborn
		    #print "  $base has head = $children[0]\n";
		}
	    } elsif (file_info($base, $relation)) {
		# use a relative path for relations we create ("head", "parent", etc.)
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
    return 1;
}

sub process_link {
    my ($node, $startflag, $depth) = @_;

    my $relation = $node->attr('rel');
    my $link = $node->attr('href');
    $link = normalize_path($base,$link) if (is_local($link));
    if ($relation eq 'source') {
	print "FILE $base GENERATED FROM: $link\n" if $warnings;
	# logic:
	#   * If we have already processed the Source Generator, continue processing.
	#   * Otherwise, flag the source as Needed, and return 0 to ignore this file for now.
	if (is_html($link)) {
	    unless (file_info($link, 'seen')) {
		file_info($link, 'needed', 1);
		file_info($base, 'needs', 1);
		return 0;
	    }
	} else {
	    print STDERR "Cannot find generator file $link in $base\n";
	    # fall through with normal processing of this file, ignoring the <link>.
	}
    } elsif ($relation =~ /^stylesheet/i) {
	$stylesheets{$link}++;
	file_info($base, 'stylesheet', $link);
    } else {
	# The root node may declare some site-wide links.
	# Other links should be created from the site content as we discover it.

	# Delete navigational links and rebuild later.  Ignore most other links.
	if ($link_relations{$relation}) {   
	    my $defer_node = 1;

	    # Some links draw their site-wide values from the root node.
	    if ($link_relations{$relation} =~ m{/}) {
		my $plain_relation = $link_relations{$relation};
		$plain_relation =~ s/[^\w]//g;
		if (is_root($base)) {
		    if ($link_relations{$relation} =~ /!/) {
			$defer_node = 0;
			file_info('/', $plain_relation, $link);
			$node -> attr('title', file_info($link, 'title'));
		    }
		}
	    }

	    if ($defer_node) {
		file_info($base, 'link_navigation',1);
		$node -> delete_node();
	    }
	}

    }
    
    return 1;
}

sub process_head {
    my ($node, $startflag, $depth) = @_;
    if (($startflag == 0) && (file_info($base, 'link_navigation'))) {
#    print "FILE: $base";
	foreach my $linkrel (keys %link_relations) {
	    my $decorated_relation = $link_relations{$linkrel};
	    next if ($decorated_relation =~ /\#/);  # do not generate
	    my $relation = $decorated_relation;
	    $relation =~ s/\W//g;
	    my $which_file = $base;
	    $which_file = file_info($base, 'parent') if ($decorated_relation =~ /\^/);
	    $which_file = file_info('/','toc') if ($decorated_relation =~ m{/});
	    my $value = file_info($which_file, $relation);
	    $value = file_info('/','toc') if ($relation eq 'toc');
	    next unless $value && ($value ne '#');
	    next if (is_root($base) && ($decorated_relation =~ m{\*}));
	    my @values = (ref($value) eq 'ARRAY') ? @{$value} : ($value); # could be one, or more.
	    foreach my $value (@values) {
		my $title = file_info($value, 'navtitle');
		$title = file_info($value, 'title') unless $title;
		$value = relative_path($base, $value);
		$node->get_previous()->push_content("<link rel='$linkrel' href='$value' title='$title'>\n");
	    }
	}
    }
}

sub process_img {
    my ($node, $startflag, $depth) = @_;

    my $preview = $node->attr('src');
    my $img_src_rel_path;
    if (is_local($preview)) {
	$img_src_rel_path = normalize_path($base,$preview);
	if ($img_src_rel_path =~ /\.(gif|jpe?g)$/) {
	    my ($file_width, $file_height) = image_size($img_src_rel_path);
	    if (!defined $file_width) {
		print STDERR "In $base : Image $img_src_rel_path not found\n";
		return;
	    }
	    my $html_width = $node->attr('width');
	    my $html_height= $node->attr('height');
	    # Correct size of images larger than 1x1 (an exception
	    # for "spacer" images).  Could be extended to give exceptions
	    # when requested size is obviously much larger or smaller
	    # than actual (e.g., wimpy thumbnails, etc.)
	    my $reset = 1;    # true if we should reset the width & height
	    $reset = 0 if ($file_width <= 1); # 1x1 expanded to fit something
	    # pictures with widths as percents also unchanged:
	    $reset = 0 if (($html_width =~ /%/) || ($html_height =~ /%/));
	    $reset = 0 if (($html_width == $file_width) && ($html_height == $file_height));
	    if ($reset) {
		# Set the correct values:
		$node->attr('width', $file_width);
		$node->attr('height', $file_height);
		print STDERR "In $base : Image size of $img_src_rel_path set to $file_width x $file_height\n";
	    }
	}
    }
    
#    print "  -> Node: [", $node->tag(), "] node's parent: [", $node->parent()->tag(), "]\n";
    if ($node->parent()->tag() eq 'a') {
	my $link = $node->parent()->attr('href');
	if (is_local($link)) {
#    print "(node's parent is <A HREF='$link'>)\n";
	    my $href_rel_path = normalize_path($base, $link);
	    my $alt_text = '';
	    
	    if ($link ne '#' && length($link) ) {		# '#' alone means no link
		$alt_text = file_info($href_rel_path,$changes{'href_alt'});
		if (defined $alt_text) {
		    $node->attr('alt',$alt_text);
		} elsif (is_html($href_rel_path)) {
		    # Remember that we must read this file later to resolve the dependency.
		    file_info($href_rel_path,'needed',1);
		    file_info($base,'needs',1);
		}
		$preview =~ s/\b(left|right|up|down)(no)?\.(gif|jpe?g)/\1.gif/;
	    } else {
		$preview =~ s/\b(left|right|up|down)(no)?\.(gif|jpe?g)/\1no.gif/;
	    }
	    $node->attr('src', $preview);
	    $node->attr('alt', $alt_text);
	    # Special navigation handling for images with names like "../nav/up.gif"
	    # so:  <a href="foo.htm"><img src="up.gif">  will add  rel="parent"   to the <a>
	    if ($preview =~ /\bnav\/(\w+)(no)?\.(gif|jpe?g)/) { # e.g., "nav/up.gif" sets $1="up"
		$node->parent()->attr('rel', $image_relations{$1}) if ($image_relations{$1});
	    }
	}
	#print "<A> with HREF= $href_rel_path and <IMG SRC>= $img_src_rel_path\n  set ALT = $alt_text\n";
    }
    return 1;
}

sub process_autosite {
    my ($node, $startflag, $depth) = @_;

    # <DIV CLASS="autosite" ID="function.with.args">...</DIV> have their
    # content removed and replaced with text from function('with','args')
    $node->delete_content(1); # delete all content
    
    # following assumes ID tag contains name of routine which generates output
    # this should be probably changed to something less prone to crash. ~~~
    my @args = split /\./, $node->attr('id'); # subroutine name and all args
    my $to_call = shift @args; # sub given first
    
    my $new_text = $to_call->(@args) if $to_call;   # soft reference

    # Now -- process *that* text as if it had occurred at this point in the file.
    $autotext++;
    my $h = new TransientTreeBuilder; 
    $h->ignore_unknown(0); $h->warn(1); $h->implicit_tags(0);
    $h->parse($new_text);
    $h->traverse(\&process_entry);   # don't you love re-entrant code?
    $node->push_content($h->as_HTML());
    $autotext--;

    return 1;
}

# -----------------------------
#
# process_entry -- main callback when traversing the parsed HTML entity tree
#
# -----------------------------

my $grab_header;  # TRUE if saving literals for <title> or <h1> .. <h6>
my $header;       # captured title
my $header_type;

sub process_entry {
    my ($node, $startflag, $depth) = @_; # startflag e.g., TRUE for <A>, FALSE for </A>

    my $tag = $node->tag();
    
    if ($grab_header) {         # save literal text in title
	if ($tag eq 'lit') { # literal text
	    $header .= $node->attr('text');
	    return 1;
	}
	if ($tag eq 'br') {		# line break in header counts as a space
	    $header .= ' ';
	    return 1;    
	}
    }

    # Find current title and possibly override
    if (($tag eq 'title') && $startflag) {	# Find current title
	file_info($base, 'title_ref', $node);	# Save reference to TITLE element in this file
    	unless (file_info($base,'title')) {	# After first reading, use title found below.
	    $grab_header = $depth;
	    $header_type = $tag;
	    $header = '';
	    print "Finding <TITLE>\n" if $debug;
	}
    } elsif (($tag =~ /^h[1-4]$/) && $startflag) {	# Override with first of H1-H4
    	if (file_info($base, 'title_override') == 0 || $node->attr('id') eq 'title') {
	    file_info($base, 'title_override', 1);
	    $grab_header = $depth;
	    $header_type = $tag;
	    $header = '';
	    print "Overriding <TITLE> with <$tag>\n" if $debug;
	}
    }

    if (($tag eq $header_type) && ($grab_header == $depth) && ($startflag == 0)) {
	# <TITLE> gets saved if defined.  Override with <H1> if present.
	# At end of <H1> save its text as the file's <TITLE>.
	$header =~ s/:?\s*$//;				# Remove any trailing colon and spaces
	file_info($base,'title',$header);		# Save title in our database
	print " Setting title of $base --> [$header]\n" if $debug;
	$grab_header = 0;
	if ($tag ne 'title') {				# Override <TITLE> with <H1>
	    my $title_ref = file_info($base, 'title_ref');	# Reference to <TITLE> entity
	    if (defined $title_ref && ref ($title_ref)) {
		$title_ref->delete_content();		# Replace existing content
		$title_ref->push_content($header);
	    }
	}
    }

    return process_head ($node, $startflag, $depth) if ($tag eq 'head');
    return process_quote ($node, $startflag, $depth) if ($tag =~ /^q|blockquote$/);
    return process_meta ($node, $startflag, $depth) if ($tag eq 'meta');
    return process_a ($node, $startflag, $depth) if ($tag eq 'a');
    return process_link ($node, $startflag, $depth) if ($tag eq 'link');
    return process_img ($node, $startflag, $depth) if ($tag eq 'img');
    return process_autosite ($node, $startflag, $depth) 
	if ($autosite_tag{$tag} && $startflag && $node->attr('class') =~ /^autosite/i);
#    return process_ ($node, $startflag, $depth) if ($tag eq '');

    return 1;
}

#-------------------
#
# Useful calls in autosite html, e.g.,
#    <div class="autosite" id="makerelative.logos">
# where logos() is a subroutine created by the Transient template
#
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
    my @children = @{file_info($node, 'child')};
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
    # omit for indented with nonbreak spaces.
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
		    foreach my $node (@{file_info($base, 'child')}) {
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
		    foreach my $node (@{file_info($parent, 'child')}) {
			$return_html .= sidenav_element($node, $indent, $style);
			next unless ($node eq $base);
			$self_listed++;
			# List our children under us
			if ($style =~ /\bchild\b/i) {
			    foreach my $node (@{file_info($base, 'child')}) {
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
    # ' # <- munchkin trick for emacs color
    #print "AFTER: [[ $text ]]\n";
    return $text;
}


#-------------------
#
# Main program
#
#-------------------

print "AutoSite Version $version  (c) Copyright wlindley.com, l.l.c.\n";

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
	
	print "Reading $base [$true_base]\n" if $warnings;
	file_info($base,'seen',1);	# Remember we have seen this file at least once.

	if (is_root($base)) {
	    # clear chapter list - we could process this node several times.
	    @saved_chapters = @chapters;
	    @chapters = ();
	}

	open FILE, $true_base;
	$text = <FILE>;
	close FILE;

        $text =~ s/<![a-zA-Z]+[^>]*>//;  # Remove offensive XML-ish tag foolishness
	$h = new TransientTreeBuilder; 

	$h->ignore_unknown(0);
	$h->warn(1);
	$h->implicit_tags(0);
	$h->parse($text);
	
	$h->traverse(\&process_entry);
	
	if (file_info($base,'needs') == 0) {
	    # All dependencies resovled.  Safe to write it out.
	    my $new_text = $h->as_HTML();
	    print "WRITING: $base [$true_base]\n" if $warnings;
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

print "File Information:\n";
foreach my $pfile (keys %file_info) {
    print "$pfile:\n";
    foreach (keys %{$file_info{$pfile}}) {
    print "  $_: [$file_info{$pfile}{$_}]\n";
}
}

__END__;
