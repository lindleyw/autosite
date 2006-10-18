#!/usr/bin/perl --

# AutoSite
# Copyright (c) 2002-2003 wlindley.com, l.l.c.   http://www.wlindley.com
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
# $Id: autosite.pl,v 1.6 2004/07/28 17:45:43 bill Exp $
#

my $debug;
my $warnings;
my $create_navigation;
my $version;

use File::Basename;
use File::Glob;
use Image::Size;


BEGIN {
  push @INC, dirname($0); # So we can find our own modules

  # CVS puts the revision here
  ($version) = '$Revision: 1.6 $ ' =~ /([\d\.]+)/;
}

use URI::URL;
use Cwd;
use relative_path;

# use  autosite.pl [-c config_file.htm] mainfile.htm
# Can specify full pathnames to either config file or main HTML file.

# -c template     Use specified template
# -w              Display warnings
# -n              Force navigational <link> elements into all files

use Getopt::Std;
BEGIN {
    # Currently the only command line argument with parameters is -c <template_file>
    getopt ('c:');
    $warnings = $::opt_w;
    $debug    = $::opt_d;
    $create_navigation = $::opt_n;
}

use TransientBaby;
use TransientBits (template_file => $::opt_c || 'site_template.html');
use TransientTreeBuilder;

# -----------------------------

sub combine_css {
    my ($hashref, $css_string) = @_;
    my %values = %{$hashref};
    while ($css_string =~ /([\w.]+)\s*:\s*([^;]+)\s*;?/g) {
      $values{$1} = $2;
    }
    return %values;
}


our %file_info;

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
    # Return a list of files which we must read to determine their contents:
    # first files we have not yet seen, then those we must revisit.
    my @unresolved;

    foreach my $select (qw{needed needs}) {
	push @unresolved, grep { length($_) &&  (file_info($_,$select) && !file_info($_,'missing')) } (keys %file_info);
    }
    return @unresolved;
}

# -----------------------------

my $toc_true_location;

sub true_location {
    # Returns the location of a file in the site (possibly with a path
    # relative to the site's home), but relative to our cwd.
    my $fname = shift;
    return undef unless defined $fname;
    return '' unless length($fname);
    return Path::normalize($toc_true_location, $fname);
}

# -----------------------------

sub is_local {
    # Returns TRUE if a file is local (e.g., not "http://...")
    my $url = shift;
    my $is_remote = ($url =~ /\:/);
    return !$is_remote;
}

my %file_type_regex = (
                     'html'  => qr/<HTML/i,
                     'style' => qr/{[^\}]+:[^\}]+;[^\}]*}/,
                     'param' => qr/^\s*\w+\s*:\s*\w+/,
                     );

sub is_file_test {
    # Returns TRUE if a file appears to be HTML, CSS, etc.
    my ($fname, $filetype, $regex) = @_;
    $regex ||= $file_type_regex{$filetype};    # Default regular expressions for known filetypes
    $filetype = "is_$filetype"; # as saved in file_info

    if (exists $file_info{$fname} && exists $file_info{$fname}{$filetype}) {
	return file_info($fname, $filetype);
    }

    # Remember and return failure
    return (file_info($fname, $filetype, 0)) unless is_local($fname);
    my $true_fname = true_location($fname);
    return (file_info($fname, $filetype, 0)) unless ((-e $true_fname) && (-T $true_fname));
    open IS_FILE, $true_fname;
    read(IS_FILE, my $header, 1024); # Assumes leading <!...> less than 1K
    close IS_FILE;
    # return TRUE if it looks like we have a start tag.  Also save the value.
    return(file_info($fname, $filetype, $header =~ /$regex/));
}

sub is_html { # test for HTML
    return is_file_test(shift, 'html');
}

sub is_style { # test for CSS
    return is_file_test(shift, 'style');
}

sub is_param {
    return is_file_test(shift, 'param');
}

#-----

sub file_contents {
    my $file = shift;
    my $file_text='';
    my $fhandle;
    open ($fhandle, "<", true_location($file)) ;
    if ($fhandle) {
      while (<$fhandle>) {
          $file_text .= $_;
      }
      close ($fhandle);
    } else {
	print STDERR "Cannot open $file: $!\n";
	return $file_text;
    }
}

sub image_size {
    # Returns width, height of image
    my $fname = shift;
    my @size = (file_info($fname,'width'),file_info($fname,'height'));
    
    return @size if ($size[0] && $size[1]); # already found
    my $true_fname = true_location($fname);
    if (-e $true_fname) {
      @size = imgsize($true_fname);      # from Image::Size
      file_info($fname,'width',$size[0]);
      file_info($fname,'height',$size[1]);
      file_info($fname,'image_type',$size[2]);
      read_param_for($true_fname);
      return @size[0,1];
    } else {
      file_info($fname,'error', "File not found: $true_fname");
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
			'prev' => 'next',     'next' => 'prev',
			'child' => 'parent',  'parent' => 'child',
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

# maps navigation images to href relations.
# for now these can only be generated relations in the file_info of that
# node, but eventually as per %link_relations.
my %image_relations = (
		       up => 'parent',
		       down => 'head',
		       left => 'prev',
		       right => 'next', 
		       first => 'first',
		       'last' => 'last'
		       );

my $image_relations = join('|', sort keys %image_relations);
my $image_relation_exp = qr/\b($image_relations)(no)?\.(gif|jpe?g)\b/;

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

# Create <LINK REL="---" HREF="---"> for HTML 4.0 capable browsers.
# NOTE: 'copyright' is handled through the <meta> tag, not here.
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
		      
		      # NOTES:
		      #  '/'  refers to root node's info
		      #  '!'  means the value will be taken from the root node, not computed.
		      #  '^'  refers to parent's info
		      #  '*'  will suppress this entry for the root node
		      #  '#'  recognizes the link as navigation on input but does not generate.
		      #  '--' suggests the <link> be untouched during processing
		      );

my $param_file_suffix = '.txt';              # if a .txt file exists for a .jpg (.gif etc) file, use that for description etc.

my %thumb_defaults = (
    'thumb.regex' => '.*\.jpe?g',
    'thumb.path'  => '.',
    
    'thumb.small.size'      => '64x64',  # could be 100x100 (max size), 5000 (max pixels), x150x130 (distorting)
    'thumb.small.generate'  => 1, 
    'thumb.small.dir'       => 'thumb',
    
    'thumb.medium.generate' => 0,
    'thumb.medium.size'     => 640*480,  # as small.size
    'thumb.medium.dir'      => 'med',
    
    'thumb.list.type'       => 'table',  # could be: p (paragraph), ul (list), table 
    'thumb.list.showsize'   => 0,        # true to show picture byte sizes
    'thumb.list.showname'   => 0,        # true to show picture names
    'thumb.list.image'      => 'small',  # could be: small, medium, large
    'thumb.list.columns'    => '3',
    'thumb.list.border'     => 1,
    'thumb.list.class'      => '',       # HTML class of thumbnail list container (like ul or table element)
    'thumb.list.entryclass' => '',       # HTML class of list entries (like li or td elements)
    'thumb.list.imageclass' => '',       # HTML class of thumbnail images
    
    'thumb.link.style'      => 'html',    # link to:  html (created from template), image (bare .jpg), none
    'thumb.link.image'      => 'medium',  # linked (target) image: small, medium, large, none (just images no links)
    'thumb.link.suffix'     => '.html',
    'thumb.link.target'     => '',        # '_blank' would create a new browser window

    'thumb.output.format'   => 'jpg',     # jpg, png
    'thumb.output.suffix'   => '.jpg',    # .jpg, .jpeg, ....etc

    'thumb.title.image'     => '',        # name of image for title.  Will create thumbdir/title.jpg
                                          # Will also create: thumb/150.jpg and thumb/200.jpg
                                          # with default title.sizes.
    'thumb.title.sizes'     => '150x130,200x150',
);

my $thumb_column = 0;

# When inheriting header information from a template
# NOTE: Most link relations are handled via %link_relations and not through
# the <meta name="inherit"> mechanism.

my %inherit_headers = (
		       stylesheet => 'link',  # stylesheets are links
		       '' => 'meta',          # everything else defaults to meta
		       );

# Maintain list of Chapters for navigation bar.
# If the site contains <A HREF="xxx" REL="chapter"> these are kept in the
#   chapter list regardless of their location
# Otherwise, all the children of the root node are assumed to be chapters.
my $site_explicit_chapters = 0; # TRUE if explicit chapters
my $chapter_group = 0;          # used in contents_of to group chapters

our $base;
our @chapters; # files which are chapters
our @saved_chapters;

my %stylesheets;
my %external_links;

# -----------------------------

sub read_data {
    my $fname = shift;   # first arg is filename to read
    my %content = @_;   # optionally followed by default values (e.g., from main template)
    
    if (-e $fname) {
      print STDERR "reading $fname\n" if $debug;
      my $template;
      local $/ = "\n";    # in AutoSite, we have undef'd $/
      open ($template, "<", $fname);
      while (<$template>) {
          my ($key, $value) = /^\s*([\w.]+)\s*:\s*(.*)$/;
          $key = lc($key);
          if ($value =~ /<<\s*(\w+)/) { # here-document
              my $stopword = $1;
              $content{$key} = '';
              while (<$template>) {
                  last if /$stopword/; # end of here-doc
                  $content{$key} .= $_;
              }
          } else {
              if ($key eq 'include') {
                  # Look for:  1) file relative to current base's directory;
                  # 2) file relative to TOC's directory
                  # ~~ Ideally, give priority to searching CALLING TEMPLATE'S directory...
                  #    which we would have to track.
                  my $fname = Path::relative($base,$value);
                  if (!is_param($fname)) {
                      my ($base_file_name,$base_file_path,$base_file_suffix) = fileparse($value,'\..*');
                      $fname = "$base_file_name$base_file_suffix"; # relative to TOC
                  }
                 if (is_param($fname)) {
                      %content = read_data(true_location($value), %content);
                  }
              } else {
                  $content{$key} = $value;
              }
          }
      }
      close ($template);
    }
    return (%content);
}

sub read_param_for {
    # Reads a parameter file (with each line in the form: "attrib: value")
    # for a given HTML or image file.  Argument is 'true_location' path.
    
    my $fname = shift;

    my ($base_file_name,$base_file_path,$base_file_suffix) = fileparse($fname,'\..*');
    my $param_file = "${base_file_path}${base_file_name}${param_file_suffix}";
    if (is_param($param_file)) {
      file_info($fname, 'param_file', $param_file);
      file_info($fname, 'params', {read_data($param_file)});
    }
}

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

#    if ($startflag) {
#	my $link = $node->attr('cite');
#	if (defined $link) {
#	    $link =~ s/#.*$//;				# Remove fragment part of link
#	    if (length($link)) {  # if it's an internal citation, it will be blank now.
#		$link = Path::normalize($base,$link) if (is_local($link));
#		# do something here? ~~~~~~~~~~~~~~
#	    }
#	}
#    }

    return 1;
}

sub process_meta {
    my ($node, $startflag, $depth) = @_;

    my $meta_name = lc($node->attr('name'));
    my $content = $node->attr('content');
    my $save_name;
    if ($saved_meta{$meta_name}) { # specifically flagged to process
	# Begin value with asterisk to inherit from TOC, if it has that value
	$save_name = $saved_meta{$meta_name};
	if ($content =~ /^\*/) {
	    my $new_content = file_info(file_info('/', 'toc'),$save_name);
	    $content = '*' . $new_content if $new_content;
	    $node->attr('content', $content);
	}
    } elsif ($meta_name =~ m{\.}) { 
	# looks like an argument we might need later (e.g., 'thumb.regex')
	$save_name = lc($meta_name);
    }

    file_info($base, $save_name, $content) if $save_name;	# Store the value

    # active processing:
    if ($meta_name =~ /^generator$/i) { # automatically update Generator
	$node->attr('content', "AutoSite $version");
    }
    if ($meta_name =~ /^inherit$/i) {   # inherit values from Template
	foreach my $value (split ( ',', $content)) {

	    $value =~ s/\s*//g; # ignore spaces
	    # <meta name="inherit" content="stylesheet"> inherits the stylesheet
	    # which is a <link>; most others are <meta>.
	    my $inherit_type  = $inherit_headers{$content} || $inherit_headers{''}; # meta or link.
	    # use <meta name="attr" content="value"> and <link rel="attr" href="value">
	    my ($inherit_attr, $inherit_value) = ($inherit_type eq 'meta') ? 
		('name', 'content') : ('rel', 'href');

	    # Starting at the root, delete all <meta> (or <link>) nodes whose
	    # name (or rel) is what we are inheriting
	    my $root = $node->root();
	    my $existing_tag;
	    while ($existing_tag = $root->find({'tag' => $inherit_type, $inherit_attr => $value})) {
		$existing_tag -> delete_node();
	    }

	    my $file_source = file_info($base, 'template') || file_info('/', 'toc');
	    my $newvalue = file_info( $file_source, $value); # value from template or site root
	    if ($inherit_value == 'href') {
		# $file_source assumed to be in site root directory
		$newvalue = Path::relative($base, $newvalue); 
	    }

	    # Add a new tag with the inherited value
	    my $newnode = TransientHTMLTreeNode->new(attribs => {'tag' => $inherit_type});
	    $newnode -> attr($inherit_attr => $value, $inherit_value => $newvalue);
	    $node -> unshift_content($newnode);
	    $node -> unshift_content("\n");
	}
    }

    return 1;
}

sub process_a {
    my ($node, $startflag, $depth) = @_;

    return 1 unless $startflag;

    my $link = $node->attr('href');
    $link =~ s/#.*$//;				# Remove fragment part of link
    return unless length($link);
    if (is_local($link)) {
	$link = Path::normalize($base,$link);
	#print "LINK TO: $link ... is_html=", is_html($link), "\n";
	if (is_html($link)) {
	    # Count links to this page
	    file_info($link, 'links_to', file_info($link, 'links_to')+1);
	}
	
	my $relation = $node->attr('rel');
	if (defined $relation) {
	    # print "in $base: $link $relation $tracked_relation{$relation} ... ", is_html($link) , " ... ", !$autotext, "\n";
	    if ($tracked_relation{$relation} && !$autotext) {
		if (is_html($link)) {
		    my %chapters = map{ $_, 1} @chapters;
		    # Chapters are automatically all children of the root node,
		    # or only those explicitly given (if at least one is explicit).
		    # Also excludes links we create automatically (as in navigation bars).
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
		    my @children = @{file_info($base, $relation) || []};
		    my %links = map { $_ => 1 } @children;
		    # print " ($base,$relation) = ", file_info($base,$relation), "\n";;
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
			push @children, $link;

			if (file_info($link, 'seen')) {
			    file_info($link, 'needed', 1); # Force re-scan of deeper files read too early
			}

			file_info($base, $relation, [@children]);  # , $link
			# print "  $base has $relation ", join(',',@{file_info($base,$relation)}),"\n";
			file_info($base,'head', $children[0]);	# remember firstborn
			file_info($base,'tail', $link);             # and lastborn
			# print "  $base has head = $children[0]\n";
		    }
		} else {
		    print STDERR "  In $base: $link not found or not HTML; ignoring.\n" if $warnings;
		}
	    } elsif (file_info($base, $relation)) {
		# use a relative path for relations we create ("head", "parent", etc.)
		my $new_href = file_info($base, $relation);
		# If it's just a fragment, don't process it as a path.
		$new_href = Path::relative($base,$new_href) unless $new_href =~ /^#/;
		$node->attr('href', $new_href);
		#print "\tSetting HREF of $relation to $new_href\n";
	    } elsif ($relation eq 'toc' || $relation eq 'contents') {
		$node->attr('href', Path::relative($base,file_info('/','toc')));
	    } else {
		# print "\tIgnoring $relation in $base\n";
	    }
	    if ($chapter_group) {  # begin a new group of chapters
		file_info($link, 'chapter_group', $chapter_group);
		$chapter_group = 0;
	    }

	}

	$link = Path::normalize($base,$node->attr('href'));		# May have been changed above.
	#print " >>> $link\n";
	if ($link eq '#') {
	    # $node->attr('alt','');			# Erase old alt text
	} elsif (is_html($link)) {
	    # Set the ALT text to the destination's title
	    my $alt_text = file_info($link,$changes{'href_alt'});
	    if (defined $alt_text || file_info($link, 'seen')) {
		$node->attr('title',$alt_text);
		#  print " >>>>>> Resolved $link ... [$alt_text]\n";
	    } else {
		# Remember that we must read this file later to resolve the dependency.
		print " >>>>>> Unresolved [$link] in [$base] ... must read it later.\n" if $debug;
		file_info($link,'needed',1);
		file_info($base,'needs',1);
	    }
	}
    } else {
	$external_links{$link}{$base}++;  # just count them.
    }
    return 1;
}

sub process_link {
    my ($node, $startflag, $depth) = @_;

    my $relation = $node->attr('rel');
    my $link = $node->attr('href');
    my $alt_link;
    my $file_type = $node->attr('type');
    $file_type = lc($1) if ($file_type =~ m{^text/(\w+)}i);     # text/css becomes just css

    if (length($link) && is_local($link)) { # It's a local (not remote) file.
	$link = Path::normalize($base,$link);  # file defaults to be relative to caller's directory

	# GOAL: Allow .html files to move around in the directory tree
	# structure.  This means that templates, and stylesheets, may
	# have wrong path information.  For these, strip path off the
	# filename.  Look in current directory first (permitting local
	# template/stylesheet overrides) and then failing that in the
	# site's root directory.

	my ($base_file_name,$base_file_path,$base_file_suffix) = fileparse($link,'\..*');
	$alt_link = "$base_file_name$base_file_suffix";  # bare filename is relative to TOC's directory
	# print STDERR " link [$link], alt_link [$alt_link]\n";
    }

    if ($relation =~ /^source$/i) {
	print "FILE $base GENERATED FROM: $link\n" if $warnings;
	if (is_html($link)) {
	    unless (file_info($link, 'seen')) {
		# flag the generating file as Needed, and return 0 to ignore this file for now.
		print "   Unresolved <link> $link in $base\n" if $debug;
		file_info($link, 'needed', 1);
		file_info($base, 'needs', 1);
		return 0;
	    }
	    # We have already generated the file; fall thru & process the result.
	} else {
	    print STDERR "Cannot find source file $link in $base\n";
	    # fall through with normal processing of this file, ignoring the <link>.
	}
    } elsif ($relation =~ /^(?:(\w+)\.)?template$/i) {
	my $template_type = $1;
	$link = $alt_link if (!is_html($link) && is_html($alt_link));
	my $rel_link = Path::relative($base, $link);
	$node -> attr('href', $rel_link);

	print STDERR "  $relation of $base is $link [$rel_link]\n" if $warnings;
	
	if ($template_type) {  # Only processing is to read in the file as plaintext
           unless (file_info($link, 'plaintext')) {
               # Read other templates as plaintext and put in file_info
               file_info($base, $relation, $link);
               file_info($link, 'template_type', $template_type);
               my $file_text = file_contents($link);
               if ($file_text) {
                   file_info($link, 'plaintext', $file_text);
                   file_info($link, 'keep_plaintext',  1);
                  file_info($link, 'readonly',  1);
                   file_info($link, 'is_html',  1);
               } else {
                   print STDERR "   Template file $link not found.\n";
                   return 0;
               }
           }
           return 1;
       }

	if (is_html($link)) {
	    unless (file_info($link, 'parse_tree')) {
		# flag the template as Needed, and return 0 to ignore this file for now.
		# even if we have seen the file before, we need to save its parse tree as a template.
		file_info($link, 'needed', 1);
		print  STDERR "  process_link: $base needs $link.\n" if $debug;
		file_info($link, 'is_template', 1);
		file_info($base, 'needs', 1);
		file_info($base, $relation, $rel_link);
		return 0;
	    }

	    # Process template
	    do_template($node, $link);

	} else {
	    print STDERR "Cannot find HTML template file $link in $base\n";
	    # fall through, ignoring the <link>.
	}
    } elsif ($relation =~ /^stylesheet/i) {
	# For convenience in editing sites and moving files into new directories,
	# this could look in a list of registered stylesheets and choose one which
	# most closely matches if the specified one is not found.  (e.g., a new file might
	# have the wrong stylesheet path from having been placed in a deeper directory level.)

	$link = $alt_link if (!is_style($link) && is_style($alt_link));
	if (is_style($link)) {
	    $stylesheets{$link}++;
	    my $rel_link = Path::relative($base, $link);
	    print STDERR "  STYLESHEET of $base is $link [$rel_link] \n" if $warnings;
	    file_info($base, 'stylesheet', $rel_link);
	    $node -> attr('href', $rel_link);
	} else {
	    print STDERR "  STYLESHEET of $base [$link] not found\n";
	}
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
    if (($startflag == 0) && (file_info($base, 'link_navigation') || $create_navigation)) {
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
		$value = Path::relative($base, $value);
		$node->get_previous()->push_content("<link rel=\"$linkrel\" href=\"$value\" title=\"$title\">\n");
	    }
	}
    }
}

sub process_img {
    my ($node, $startflag, $depth) = @_;

    my $preview = $node->attr('src');
    my $img_src_rel_path;
    if (is_local($preview)) {
	$img_src_rel_path = Path::normalize($base,$preview);
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
		print STDERR "In $base : Image size of $img_src_rel_path set to $file_width x $file_height\n" if $warnings;
	    }
	}
    }
    
#    print "  -> Node: [", $node->tag(), "] node's parent: [", $node->parent()->tag(), "]\n";
    if ($node->parent()->tag() eq 'a') {
	my $link = $node->parent()->attr('href');
	if (is_local($link)) {
	    # Special navigation handling for images with names like "../nav/up.gif"
	    # so:  <a href="foo.htm"><img src="up.gif">  will add  rel="parent"   to the <a>
	    my $nav_link = ($preview =~ /$image_relation_exp/);

	    # Create relation automatically if none given.  Re-process <A> tag.
	    if ($nav_link && !$node->parent()->attr('rel')) { # e.g., "nav/up.gif" sets $1="up"
		$node->parent()->attr('rel', $image_relations{$1});  # $1 from regexp above
		process_a($node->parent(), 1, 0);
		$link = $node->parent()->attr('href'); # find new link
	    }

	    my $href_rel_path = Path::normalize($base, $link);
	    my $alt_text = '';

	    if ($link ne '#' && length($link) ) {
		$alt_text = file_info($href_rel_path,$changes{'href_alt'});
		if (defined $alt_text) {
		    $node->attr('alt',$alt_text);
		} elsif (is_html($href_rel_path)) {
		    # Remember that we must read this file later to resolve the dependency.
		    print "   Unresolved <href> $href_rel_path in $base\n" if $debug;
		    file_info($href_rel_path,'needed',1);
		    file_info($base,'needs',1);
		}
		$preview =~ s/$image_relation_exp/$1.$3/o;  # wl 2003-10-04
	    } else {
		$preview =~ s/$image_relation_exp/$1no.$3/o; # wl 2003-10-04
	    }
	    $node->attr('src', $preview);
	    $node->attr('alt', $alt_text);
	}
	# print "in $base: <A> with HREF= $href_rel_path and <IMG SRC>= $img_src_rel_path\n  set ALT = $alt_text\n";
    }
    return 1;
}

sub process_autosite {
    my ($node, $startflag, $depth) = @_;
    my $replacement_text;
    my $skip_created_relations = 1; # by default, any children or other tracked relations
       # created by autosite code are ignored.

    if ($startflag && $node->attr('class') =~ /^chapter_group/i) {
	$chapter_group = $node->attr('title') || '~~';  # either the title, or '~~' for default
    } elsif ($startflag && $node->attr('class') =~ /^subtemplate/i) {
      # <div class="subtemplate" title="param=value; param=value">
      do_subtemplate($node);
    } elsif ($startflag && $node->attr('class') =~ /^thumbnail/i) {
      # <div class="thumbnail" title="param=value; param=value">
# Until code is enabled -- wl 2005-10-20
#      $replacement_text = do_thumbnails($node->attr('title'));
      $skip_created_relations = 0; # actually consider created children
    } elsif ($startflag && $node->attr('class') =~ /^autosite/i) {
	# <DIV CLASS="autosite" ID="function.with.args">...</DIV> have their
	# content removed and replaced with text from function('with','args')

	# The following assumes ID tag contains name of routine which
	# generates output.  Call of arbitrary function might be
	# unsafe, should be probably changed to code like
	# tag_processor below.
	my @args = split /\./, $node->attr('id'); # subroutine name and all args
	my $to_call = shift @args; # sub given first
    
	{
           no strict;
           $replacement_text = $to_call->(@args) if $to_call;   # soft reference
	}
    }
	
    # Process replacement text as if it had occurred at this point in the file.
    if (length ($replacement_text)) {
	$node->delete_content(1); # delete all content
	$autotext += $skip_created_relations;
	my $h = new TransientTreeBuilder; 
	$h->ignore_unknown(0); $h->warn(1); $h->implicit_tags(0);
	$h->parse($replacement_text);
	$h->traverse(\&process_entry);   # don't you love re-entrant code?
	$node->push_content($h->as_HTML());
	$autotext -= $skip_created_relations;
    }

    return 1;
}

sub process_stopped {
    my ($node, $startflag, $depth) = @_;

    my $error =  "ERROR in $base -- cannot parse at approximately:\n" .  substr($node->attr('text'), 0, 80), "\n";
    # print $error;
    # print STDERR $error;
    die $error;
}


# -----------------------------
#
# process_entry -- main callback when traversing the parsed HTML entity tree
#
# -----------------------------

my $grab_header;  # TRUE if saving literals for <title> or <h1> .. <h6>
my $header;       # captured title
my $header_type;

my %tag_processor = (
		     'head'       => \&process_head,
		     'blockquote' => \&process_quote,
		     'q'          => \&process_quote,
		     'meta'       => \&process_meta,
		     'a'          => \&process_a,
		     'link'       => \&process_link,
		     'img'        => \&process_img,
# These tags, with CLASS="autosite" ID="function.param.param" will
# cause a subroutine call:
		     'ins'        => \&process_autosite,
		     'div'        => \&process_autosite,
		     'span'       => \&process_autosite,
		     'stopped'    => \&process_stopped,
		     );

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

    if (defined $tag_processor{$tag}) {
	return $tag_processor{$tag}->($node, $startflag, $depth) ;
    }

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

sub param { # Insert a parameter from the accompanying text file.
    my ($param) = @_;
    my $parameters = file_info($base, 'params');
    if (ref $parameters eq 'HASH') {  # retrieve from text parameter file.
      my $value = $$parameters{$param};
      return $value if defined $value;
    }
    return file_info($base, $param);  # fall back to returning file's global parameter (e.g., 'title')
}

######################

sub _contents_of {
    my ($node, $level, $style, $recurse) = @_;
    my ($my_html, $pre_html, $post_html, $my_pre_html, $my_post_html);
    my $id = ($node eq $base) ? 'current-nav' : '';  # current-nav ID so we can set <STYLE>
    my $title = file_info($node, 'navtitle');  # Default to navigation title
    if (($style =~ /\bfull\b/i) || length($title) == 0) { # wants full title, or no navigation title
	$title = file_info($node, 'title') ;
    }
    my $link_html = linkify(Path::relative($base, $node), $title, chapter_type($node),$id);

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
    } elsif ($style =~ /\bbullets?\b/i) {
	$my_html = "<nobr>&#149; $link_html</nobr> ";
    } else {
	$my_html = '&nbsp' x ($level * 2) . $link_html . "<BR>\n";
    }

    my $html = '';
    $html = $my_pre_html;
    my @children = @{file_info($node, 'child') || []};
    if (scalar @children) {
	$html .= "$my_html$pre_html";
	foreach (@children) {
#	    if (file_info($_, 'needed')) {    # We depend on all files
	    unless (file_info($_, 'seen')) {    # Wait until all files are seen once
		# (seen, not necessarily totally finished, to eliminate infinite dependency)
		print "        Child $_ not yet read.\n" if $debug;
		$html = '~~~unresolved~~~';   # so if there is even one file not yet read in,
		break;                        # stop now and flag the calling file with Needs.
	    }
	    $html .= _contents_of($_, $level + 1, $style, $recurse);
	}
	$html .= $post_html;
    } else {
	$html .= $my_html;
    }
    $html .= $my_post_html;
    return $html;
}

sub _contents {
    # Base routine for contents() and full_contents()
    my ($root, $style, $recurse) = @_;
    print STDERR "_contents ($root, $style, $recurse)\n" if $debug;
    my $level = 0;
    my $html = '';

    my $content_table = _contents_of($root, $level, $style, $recurse);
    if ($content_table =~ '~~~unresolved~~~') {
	file_info($base, 'needs', 1); # Build this page only after all other files read in.
	print "_contents:  $base must wait because content_table is:  [$content_table]\n" if $debug;
    } else {
	$html .= $content_table;
    }
    return $html;
}

sub contents {
    # Return html containing indented tree with nested contents of current node
    my $style = shift;
    return _contents($base, $style, 1);
}

sub children {
    # Return html containing indented tree with contents of current node,
    # next-level documents (children) only
    my $style = shift;
    return _contents($base, $style, 0);
}

sub full_contents {
    # Return html containing indented tree with contents of entire site
    # in HTML:
    #    <span class="autosite" id="full_contents.ul"></span>
    # or <span class="autosite" id="full_contents.ol-1Aia"></span>
    # 'ul' means use Unordered list; 'ol' means ordered list;
    # omit for indented with nonbreak spaces.
    my $style = shift;
    my $recurse = ($style =~ /\btop\b/) ? 0 : 1 ; # top only?  default is all.
    return _contents(file_info('/', 'toc'), $style, $recurse);
}

######################

sub sidenav_element {
    my ($node, $level, $style) = @_;
    my $divider_prefix;
    my $link_prefix;
    my $link_suffix = "<BR>\n";

    unless (file_info($node, 'seen')) { # flag forward reference
	file_info($base, 'needs', 1);
    }

    # title will be navigation-title, else regular title
    my $node_title = file_info($node, 'navtitle') || file_info($node, 'title'); 

    my $group_heading = file_info($node, 'chapter_group');
    if ($group_heading) {
	$divider_prefix = "<HR>";
	if ($group_heading ne '~~') {  # other than default horiz-rule-only
	    $divider_prefix .= "\n<p class='chapter_group'>$group_heading</p>\n";
	}
    }

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
    } elsif ($style =~ /\b(ul|ol)\b/) { # ordered or unordered list
	$link_prefix = "<li>";
	$link_suffix = "</li>";
    } else {
	$link_prefix = "&nbsp;&nbsp;" x $level;
    }
    my $link_html = linkify(Path::relative($base, $node), $node_title,
			    $nav_class, $nav_id, $nav_style);
    return "$divider_prefix$link_prefix$link_html$link_suffix";
}

sub sidenav_list {
    my ($level, $style, $exiting) = @_;
    my $html_modifier = '';
    
    if ($style =~ /\b(ul|ol)(?:-(\w+))?/) {  # use (un)ordered list
	if (!$exiting) {
	    $html_modifier .= ' class="sidenavlist"';
	    if ($2) {
		$html_modifier .= ' type="' . substr($2, $level, 1) . '"';
	    }
	}
	return ($exiting ? "</$1" : "<$1") . $html_modifier . ">\n";
    }
    return '';
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

    $return_html .= sidenav_list(0, $style, 0); # optionally enter list

    # trace ancestry back to the first generation (TOC)
    if ($parent eq $adam) {
	$ancestor = $base; # We are Adam, the TOC.
	@use_chapters = @saved_chapters;  # The array from last iteration
 	$return_html .= sidenav_element($base, 0, $style);
    } else {
	while (($parent ne $adam) && length($parent)) {
	    $ancestor = $parent; 
	    unshift @begats, $parent;
	    if (file_info($parent, 'needed')) {
		file_info($base, 'needed', 1);  # Haven't read parent yet, rescan this file later.
	    }

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
		    $return_html .= sidenav_list($indent, $style, 0); # optionally enter list
		    foreach my $node (@{file_info($base, 'child') || []}) {
			$return_html .= sidenav_element($node, $indent + 1, $style);
		    }
		    $return_html .= sidenav_list($indent, $style, 1); # end list
		}
	    	next;
	    }
	    foreach my $node (@begats) { # includes our parent and us.
	    	next if (($node eq $base) && $self_listed);
		$return_html .= sidenav_element($node, $indent++, $style);
		# List our siblings under our parent
		if ($node eq $parent) {
		    $return_html .= sidenav_list($indent, $style, 0); # optionally enter list
		    foreach my $node (@{file_info($parent, 'child') || []}) {
			$return_html .= sidenav_element($node, $indent, $style);
			next unless ($node eq $base);
			$self_listed++;
			# List our children under us
			if ($style =~ /\bchild\b/i) {
			    $return_html .= sidenav_list($indent, $style, 0); # optionally enter list
			    foreach my $node (@{file_info($base, 'child') || []}) {
				$return_html .= sidenav_element($node, $indent + 1, $style);
			    }
			    $return_html .= sidenav_list($indent, $style, 1); # end list
			}
		    }
		    $return_html .= sidenav_list($indent, $style, 1); # end list
		}
	    }
	} else { # Chapter, but not our ancestor
	    $return_html .= sidenav_element($_, 0, $style);
	}
    }
    $return_html .= sidenav_list(0, $style, 1); # end list
    return $return_html;
}

# ----------------

sub _makerelative {
    # Changes HTML which is written to be relative to the site's root, to be relative
    # to the given file.
    # ~~~ Ideally, change this to permit the original HTML to be relative to anywhere
    # in the site, but currently $old_base is ignored.
    my ($text, $old_base, $new_base) = @_;
    # print "makerelative:  [[ $text ]] -> ";
    $text =~ s/(href|src|background)\s*=\s*"([^#\"]+)(\#[^\"]*)?"/"$1=\"" . Path::relative($new_base,$2) . "$3\""/sgie;
    # print "[[ $text ]]\n";
    return $text;
}

sub makerelative {
    # This calls a function, takes the HTML it returns, and rewrites
    # the links in it to be relative to the current page instead of the
    # document root.  NOTE: Must not process the "#anchor" part.
    my $func = shift;
    
    my $text;
    {
      no strict;
      $text = $func->();
    }
    return _makerelative($text, undef, $base);
}

# ----------------
# Thumbnails
# ----------------

sub thumb_open {
    my %thumb = @_;

    if ($thumb{'list.type'} eq 'table') {
	return "<TABLE><TR>\n";
    } elsif ($thumb{'list.type'} eq 'ul') {
	return "<UL>\n";
    }
}

sub thumb_close {
    my %thumb = @_;

    if ($thumb{'list.type'} eq 'table') {
	return "</TABLE>\n";
    } elsif ($thumb{'list.type'} eq 'ul') {
	return "</UL>\n";
    }
}

# Make the thumbnails, and emit the text, for one input file.
sub thumb_make {
    my $file = shift;
    my $link_text = $file;  # hack for now

    if ($thumb{'list.type'} eq 'table') {
	return "<td>$link_text</td>\n";
    } elsif ($thumb{'list.type'} eq 'ul') {
	return "<li>$link_text</li>\n";
    } else {
	$text .= "<P>$link_text</P>";
    }

}

sub thumbnails {
    # Insert thumbnails of images in current directory.
    # Can create links, and even "child" pages (as a side effect).
    # NOTE: Eventually, process_meta should handle arrays so we can have multiple
    # thumb.regex entries, so we can have several possible matches, sorted how we want.
    my $text;
    my $column = 0;
    my $total_size = 0;

    my %thumb;
    foreach (keys %thumb_defaults) {
	my $newvalue = $_; $newvalue =~ s/^thumb\.//;
	$thumb{$newvalue} = file_info($base, $_) || $thumb_defaults{$_};
    }

    print STDERR "foo!";
    opendir (THISDIR, $thumb{'path'}) or return "<!-- cannot open $thumb{'path'} -->";
    my @allfiles = readdir THISDIR;
    closedir THISDIR;
    print STDERR @allfiles;

    # Gradually transferring stuff from makeindex.pl -- wl 2003-07-16

    $text .= thumb_open(%thumb);
    foreach my $file (@allfiles) {
	if ($file =~ /$thumb{'regex'}/) {  # matches regex / wildcard ... produce a thumbnail
	    thumb_make($file);
	}
    }
    $text .= thumb_close(%thumb);
    $text .= "$total_files files, totalling $total_size bytes.\n" if ($thumb{'showsize'});

    return $text;
}

#-------------------
#
# Templates
#
#-------------------

sub do_template {
    # Replace the body of the current file, except the content section, with the
    # body of the template.  Place our content section where the template's content was.

    my ($node, $link) = @_;
    my %content_division = ('tag' => 'div', 'id' => 'content');

    my $template = file_info($link, 'parse_tree');
    unless ($template) { # rely on caller to do this bookkeeping
	print STDERR "Cannot find content for $link\n";
	return 0;
    }
    $template = $template->{root}; # root node of HTML Tree

    my $main_html = $node->root();   # root of current parse tree

    # find template body and make a copy
    my $template_body = $template->find({'tag' => 'body'});
    unless ($template_body) {
	print STDERR "No body in $link, cannot create from template.\n";
	return 0;
    }
    unless ($template_body->find(\%content_division)) {
	print STDERR "Template $link does not contain a content division!\n";
	return 0;
    }
    $template_body = $template_body->get_child()->copy();

    # copy existing content
    my $main_content = $main_html->find(\%content_division);
    $main_content = $main_content->get_child()->copy() if $main_content;
    unless ($main_content) {
	print STDERR "No content section in $base, cannot create from template.\n";
	return 0;
    }

    # replace the body with the template's body
    my $main_body    = $main_html->find({'tag' => 'body'});
    unless ($main_body) {
	print STDERR "No body in $base, cannot create from template.\n";
	return 0;
    }
    $main_body -> delete_content(1);
    $main_body -> push_content($template_body);
    
    # replace the content division (in the body from the template) with our content division
    my $new_content = $main_html ->find(\%content_division);
    if ($new_content) {
	$new_content -> delete_content(1);
	$new_content -> push_content($main_content);
    }

}

sub do_subtemplate {
    # The enclosed HTML becomes a new (internal) template from which children
    # HTML files will be created.
    my ($node) = @_;
    
    # Add parameters (as: "source: images; images: *.jpg *.gif; thumb.size: 100x100") to file info
    my $info_text = $node->attr('title');
    my %info;
    my $param_ref = file_info($base,'params');
    if (ref $param_ref eq 'HASH') {
      %info = $$param_ref;
    }
    %info = combine_css( \%info, $info_text);    # Combine that with the "value: attrib; value: attrib" parameters
    file_info($base, 'params', \%info);


    # Create a copy of our parse tree under an internal name.  Make a
    # scratch copy of the subtemplate division.  In the parse tree
    # copy, replace the contents of the 'content' division with that
    # of the 'subtemplate' division.

    # For each the files to be created (look in the 'images' parameter)
    # make an HTML file which is just a copy of the newly made template
    # (derived from the original subtemplate).  Make these new HTML files
    # children of the original file.


    # PLAN:  use parameters like this --
    #    source:   can be
    #        'images'      (list of images from parameter, turned into thumbnail links)
    #        'text'        (list of text files to be turned into HTML)
}

#-------------------
#
# File I/O
#
#-------------------

sub read_file {
    my $base = shift;
    my $true_base = true_location($base);
    my $parse_tree;

    # Read file and parse its HTML unless we have already done so.
    unless ($parse_tree = file_info($base, 'parse_tree')) {
	my $text;
	if ($text = file_info($base, 'plaintext')) {
	    if (file_info($base, 'keep_plaintext')) {   # Remove as we are parsing here.
		return 1;
	    } else {
		# Force processing of HTML.
		file_info($base, 'plaintext', undef);
	    }
	} else {
	    open FILE, $true_base;
	    $text = <FILE>;
	    close FILE;
	}
	
	$text =~ s/<![a-zA-Z]+[^>]*>//;  # Remove offensive XML-ish tag foolishness
	$text =~ s{/>}{>}g;              # likewise XMLishness
	$parse_tree = new TransientTreeBuilder; 
	
	$parse_tree->ignore_unknown(0);
	$parse_tree->warn(1);
	$parse_tree->implicit_tags(0);
	$parse_tree->parse($text);
    }
    return $parse_tree;
}

sub write_file {
    # Writes a parsed file to disk
    my $fname = shift;
    my $parse_tree = shift || file_info($fname, 'parse_tree');

    unless ($parse_tree) {
	print STDERR "  ERROR! No Parse Tree for $fname\n";
	return 0;
    }
    my $true_base = true_location($fname);
    unless (file_info($fname, 'readonly')) {   
	# stripped template sources are readonly so we don't gut the disk files
	my $new_text = $parse_tree->as_HTML();
	$new_text =~ s/\n{3,}/\n/g;    # bleurgh, happens with deletions of tags
	print "WRITING: $fname [$true_base]\n" if $warnings;
	open FILE, ">$true_base";
	print FILE $new_text;
	print FILE "\n";
	close FILE;
    }
}

#-------------------
#
# Website report
#
#-------------------

sub write_report {
    open REPORT, "> _report.html";
    print REPORT "<html><head><title>Website Report</title></head><body>\n";
    
    print REPORT "<h1>Website Report as of " . scalar localtime() . "</h1>\n";
    
    print REPORT "<h2>Chapters</h2>\n";
    if (@chapters) {
	print REPORT "<ul>";
	foreach (@chapters) {
	    print REPORT "<li><a href='$_'>$_</a> " . (file_info($_, 'chapter') || '(implicit)') . "</li>\n";
	}
	print REPORT "</ul>\n";
    } else {
	print REPORT "<p>(none)</p>\n";
    }
    
    print REPORT "<h2>External Links</h2>\n";
    print REPORT "<table><tr><th>Link<th>from...</tr>\n";
    foreach my $extfile (sort keys %external_links) {
	print REPORT "<tr><td valign='top'><a href='$extfile'>$extfile</a></td><td>\n";
	foreach my $linkfrom (keys %{$external_links{$extfile}}) {
	    print REPORT "<a href='$linkfrom'>$linkfrom</a> ";
	}
	print REPORT "</td></tr>\n";
    }
    print REPORT "</table>\n";
    
    use attributes;
    
    print REPORT "<h2>File Information</h2>\n";
    print REPORT "<blockquote><table>\n";
    foreach my $pfile (sort keys %file_info) {
	my @infos = sort keys %{$file_info{$pfile}};
	my $info_count = scalar @infos || 1;
	print REPORT "<tr><td valign='top' rowspan='$info_count'><a href='$pfile'>$pfile</a></td>\n";
	foreach (@infos) {
	    print REPORT "<td valign='top'>$_</td><td>";
	    my $value = $file_info{$pfile}{$_};
	    if ($value =~ /\.html?$/ && is_html($value)) {
		$value = "<a href='$value'>$value</a>";
	    }
	    if ($debug) {   # Prettyprint a single level of hash
		if (ref ($value) && attributes::reftype($value) eq 'HASH') {
		    my %hashvalue = %{$value};
		    $value = "<table>\n";
		    foreach (sort keys %hashvalue) {
			$value .= "<tr><td>$_</td><td>$hashvalue{$_}</td></tr>\n";
		    }
		    $value .= "</table>\n";
		}
	    }
	    print REPORT "[$value]</td></tr>\n";
	}
	print REPORT "<tr><td colspan='3'><hr width='100%'></td></tr>\n";
    }
    print REPORT "</table></blockquote>\n<hr>";
    
    close REPORT;
}

#-------------------
#
# Main program
#
#-------------------

print "AutoSite Version $version  (c) Copyright wlindley.com, l.l.c.\n";

use File::DosGlob 'glob';  # override CORE::glob

undef $/;

unless (scalar @ARGV) {
    print "Use:   autosite [-c site_template_file] index.html\n";
    exit;
}

my @basefiles = glob $ARGV[0];

$toc_true_location = $basefiles[0]; # First file is actual base, possibly with path

foreach $base (@basefiles) {
    unless (defined $base) {
        die "Must specify input file.\n";
    }
    $base = Path::relative($toc_true_location, $base); # use file's relative location in site
    file_info("/","toc",$base) unless file_info("/","toc"); # Set collection's toc
    file_info($base,'needed',1);	# Set "Needed by other files" flag
}

while (scalar (@files = unresolved())) {
    # print STDERR "Unresolved: ", join(',', @files), "\n" if $warnings;

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


       # Thumbnail templates and similar files are not actually part of the site
       next if (file_info($base, 'plaintext') && file_info($base,'readonly'));

	# Parse file's HTML, from cache if possible.
       $h = read_file($base);
       unless ($h) {
           print stderr "  ERROR: Cannot parse $base.\n";
           next;
	}
	    
	$h->traverse(\&process_entry) if ref($h);
	
	# if 'seen' 1, it's our first time thru... might have forward references within.
	file_info($base,'seen', file_info($base, 'seen') + 1);

	if (file_info($base,'needs') == 0) {
	    # All dependencies resovled.  Safe to write it out.
	    write_file($base, $h);
	} else {
	    print "     Flagged for reprocess: $base\n" if $debug;
	    file_info($base,'needed',1);	# Show we must process it again
	}

	# Either save or dispose of the HTML parse tree
	if (file_info($base, 'is_template')) {
	    print STDERR "Saving template $base\n" if $debug;
	    # Remove items processed by TransientBits
	    file_info($base, 'readonly', 1); # Do not save stripped version!
	    foreach my $remove_transient qw(form email macro) {
		my $node;
		while ($node = $h->{root}->find({'class' => $remove_transient})) {
		    # delete the closing tag
		    my $tag = $node->attr('tag');
		    if ($node -> get_next -> attr('tag') eq "/$tag") {
			$node->get_next->delete_node();
		    }
		    $node -> delete_node();
		}
	    }
	}

	if (file_info($base, 'is_template')) {
	    file_info($base, 'parse_tree', $h) unless file_info($base, 'parse_tree');
	} else {
	    $h->delete();
	}

    }
}

write_report();

__END__;
