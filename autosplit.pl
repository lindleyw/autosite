#!/usr/bin/perl --

# AutoSplit
# Copyright (c) 2002 wlindley.com, l.l.c.   http://www.wlindley.com
#
# Parse an HTML file which will serve both as a template and as
# the content for a website (or a portion of a website).  Find the
# <DIV> with ID="content", and use the <DIV> tags nested therein
# as the content.  The <DIV STYLE="filename=foo"> will output either
# foo/index.html (if that DIV contains other DIV tags) or foo.html.
#
# Written and maintained by William Lindley   wlindley@wlindley.com
#

#################################
#
# NOTES:
#
# The root document (specified on the command-line) will be the 'toc' for
# the entire collection of documents.  This is useful for the site's home-page.
# Documents containing "child" links will "adopt" their children, and any child's
# "parent" link will automatically be updated to its adoptive parent.
#
# The main <body> will serve as the template, with each <div id="content"> becoming a separate file.
# In each <div> you can put in the title attribute:
#	filename:foo		creates foo.html
#	title:My Page		sets the page's title
#	navtitle:Page		sets the page's name in the navigation bar
#
#
#  use   <div title="filename: foo">  now, since Mozilla Composer and
#    others discard 'illegal' style names
#  can use  <span class="authoring">  or   <span class="suppress">  to
#    suppress enclosed text, useful for notes to self or markup to
#    delineate sections during authoring
#  use the id attribute to create hyperlinks within a collection of documents.
#    A relative path will be created.  For example, if you create
#    <h1 id="kumquat">  and elsewhere use   <a href="#kumquat">  that link
#    will point to #kumquat in the correct file in your collection (e.g.,
#    "./fruits.html#kumquat"
#
#################################

use File::Basename;

use URI::URL;
use Cwd;

BEGIN {
    push @INC, dirname($0); # so we can find our own modules
}

BEGIN {
  push @INC, dirname($0); # So we can find our own modules

  # CVS puts the revision here
  ($version) = '$Revision: 1.5 $ ' =~ /([\d\.]+)/;
}

# use:  autosplit.pl mainfile.htm
# Can specify full pathnames to either config file or main HTML file.

use Getopt::Std;
BEGIN { getopt ('c:');  print "[[[$opt_c]]]\n";}

my $warnings = $opt_w;

    use TransientBaby;
#    use TransientBits;
#    use TransientHTMLTree;
    use TransientTreeBuilder;

# -----------------------------

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

#    print "  ($from_file_path, $to_file_path)\n";
#    print "  from_paths: ", join(' ', @from_paths), "\n";
#    print "  to_paths:   ", join(' ', @to_paths), "\n";

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

sub is_local {
    # Returns TRUE if a file is local (e.g., not "http://...")
    my $url = shift;
    my $is_remote = ($url =~ /\:/);
    return !$is_remote;
}

# -----------------------------


# -----------------------------

my $unique_replace;
my $info_tag = 'title';         # tag in <DIV> elements containing our info.  Originally 'style', now generally 'title'.

my $template_html;
my $content_html;

sub make_template {
    my ($node, $startflag, $depth) = @_; # startflag e.g., TRUE for <A>, FALSE for </A>

    my $tag = $node->tag();

    if (($tag eq 'div') && $startflag && ($node->attr('id') =~ /^content$/i)) {
	# Content division.  Note that this has <div id="content"> and because id's share a
	# namespace, you can use <a href="filename.html#content"> to refer the content
	# of any template-generated file.
	$content_html = $h -> regen($node);	# save interior content (global var.)
	$node->delete_content(1);		# Remove all existing content
	$node->push_content($unique_replace);	# temporarily replace with unique code
	# Info_tag being 'title' is preferable, as the 'style' of the template's <div id='content'> flows thru.
	# Original use of 'style' deprecated as template HTML can't be properly edited with Mozilla Composer
	# which enforces valid style tag components.
	if ($node->attr('title') !~ /:/) { 
	    $info_tag = 'style';                # use <div style="key: value">
	}
	$node->attr($info_tag,'');              # erase template's info in created pages
    }
}

my @division_stack;
my %division_text;
my %division_info;
my $saving_title = 0;		# ugly global hack for saving page titles
my %anchor_file;                # remember file for each anchor defined with id=''
my $chapter_group = 0;
my $chapter_group_count = 0;

my %suppress_class = ( 'suppress' => 1, 'authoring' => 1 );

sub split_content {
    my ($node, $startflag, $depth) = @_; # startflag e.g., TRUE for <A>, FALSE for </A>
    my $tag = $node->tag();
    my $current_division = join('/', @division_stack);

    # Within the <DIV id="content"> there may be multiple divisions, like this:
    #    <DIV class="content" title="navtitle: My Page; filename: mypage">
    # which would create mypage.html with navigation title "My Page"...

=pod
    print " " x $depth, $startflag ? "$tag:" : "/$tag:";
    if ($tag eq 'lit') {
	my $littext = $node->attr('text');
	$littext =~ s/\n/\\n/gs;
	print " ($littext)";
    }
    print " class='", $node->attr('class'), "'";
    if ($node->get_previous()) {
	print "... Previous: tag='", $node->get_previous->attr('tag'), "', id='", $node->get_previous->attr('id'), "', class='", $node->get_previous->attr('class'), "'";
    }
    if ($node->parent()) {
	print "... Parent: tag='", $node->parent->attr('tag'), "', id='", $node->parent->attr('id'), "', class='", $node->parent->attr('class'), "'";
    }
    print "\n";
=cut

    if ($tag eq 'div') {
	my $id = $node->attr('id');
	my $class  = $node->attr('class');
    	if ($startflag) {
	    if ($node->attr('class') =~ /^content$/i) { # Content divisions get split into subsections.
		my $info_text = $node->attr($info_tag);
		print "$current_division: id = $id class = $class info = $info_text\n" if $warnings;
		my %info;
		$info_text =~ s/(\&\w+);/$1~~~/g;   # permit &amp; for example.
		while ($info_text =~ /(\w+)\s*:\s*([^;]+)\s*;?/g) {
		    $info{$1} = $2;
		    $info{$1} =~ s/~~~/;/g;
		}
		
		$division_info{$current_division}{'children'}++;
		#print "filename = $info{'filename'}  current_division = $current_division\n";
		
		# Create a new child
		push @division_stack, $info{'filename'};
		# die "Nameless child in " . join('|', @division_stack) unless $info{'filename'};
		
		my $new_division = join('/', @division_stack); # this will be its name
		print "Creating: $new_division\n" if $warnings;
		# remember it as our child
		push @{$division_info{$current_division}{'child_list'}}, $new_division; 
		$division_info{$new_division} = \%info;
		
		# only root node may and must have id="content" .
		$division_info{$new_division}{'is_root'} = ($id eq 'content');

		# Save title, navigation title, and chapter group heading
		foreach my $save (qw(title navtitle)) {
		    if ($info{$save}) {
			$division_info{$new_division}{$save} = $info{$save};
		    }
		}
		$division_info{$new_division}{'chapter_group'} = $chapter_group if $chapter_group;
		    
	    } elsif ($node->attr('class') =~ /^chapter_group$/i) { # Content divisions get split into subsections.
		$chapter_group = $node->attr('title') || ('~~' . ++$chapter_group_count); # actual title or '~~' for "blank but present"
	    } else {
		$division_text{$current_division} .= $node->element_html();
	    }
	} else {
	    if ($node->get_previous()->attr('class') =~ /^content$/i) {
		pop @division_stack;
	    } elsif ($node->get_previous()->attr('class') =~ /^chapter_group$/i) {
		$chapter_group = 0;
	    } else { # other division types go into text stream.
		$division_text{$current_division} .= "</div>"; # element_html() gives '<div>' not '</div>' here ???
	    }
	}
    } else {
	if ($tag =~ /^h\d/) {
	    if ($startflag) {
		unless (length($division_info{$current_division}{'title'})) {
		    $saving_title = 1;
		}
	    } else {
		$saving_title = 0;
	    }
	} elsif ($tag eq 'lit' && $saving_title) {
	    $division_info{$current_division}{'title'} .= $node->attr('text');
	} elsif ($tag eq 'br' && $saving_title) {
	    $division_info{$current_division}{'title'} .= ' ';  # line break becomes space in title
	}
	my $id = $node->attr('id');
	if ($id) {
	    $anchor_file{$id} = $current_division;
	}
	if ($startflag && $suppress_class{$node->attr('class')}) {
	    # Suppress this node, its contents, and any matching ending tag.
	    $node->delete_content(1);
	    my $next_node = $node->get_next();
	    if ($next_node && $next_node->attr('tag') eq "/$tag") {
		$next_node->delete_node(); # Also remove closing tag
	    }
	} else {
	    # Save text of this HTML entity
	    $node->attr('tag', "/" . $node->attr('tag')) unless $startflag;  # Rebuild ending nodes
	    $division_text{$current_division} .= $node->element_html();
	}
    }
}

my $relative_current_node;  # ugly global var hack

# Which attribute link to make relative for the given tags.
my %attrib_edits = (
    'link' => 'href', 'a' => 'href',
    'img'  => 'src',  'td' => 'background',
);

sub make_links_relative {
    my ($node, $startflag, $depth) = @_; # startflag e.g., TRUE for <A>, FALSE for </A>
    my $tag = $node->tag();
    my $attrib_to_edit;

    my $fname = normalize_path($base, split_filename($relative_current_node));

    $attrib_to_edit = $attrib_edits{$tag};
    if ($attrib_to_edit) {
	my $value = $node->attr($attrib_to_edit);
	if ($value && is_local($value)) {
	    # Intrapage fragments become intrasite links.
	    # Assume the 'foo' division contains a subdivision 'bar'
	    # with a tag <h2 id='blech'> ... in foo/ is quux.pdf and
	    # in the site's root directory is blort.jpg .
	    #
	    #  href="#bar"       =>  "bar/index.html"       (top of page)
	    #  href="#bar#"      =>  "bar/index.html#bar"   (at that fragment)
	    #  src="blort.jpg"   =>  "../blort.jpg"         (from foo/ back to parent, based off root)
	    #  href="./quux.pdf" =>  "./quux.pdf"           (relative to actual location)
	    if ($value =~ /^\#(\w+)(\#?)/) {
		my $anchor = $anchor_file{$1};
		my $fragment = $2 ? "#$1" : ''; # Use "#foo#" to get "category/index.html#foo"
		my $dest_file = split_filename($anchor);
		if ($anchor && $dest_file) {
		    my $relative_file = relative_path($fname, normalize_path($base, $dest_file));
		    $node->attr($attrib_to_edit, "$relative_file$fragment");
		} else {
		    print STDERR "  Unresolved link #$1 in $base\n";
		}
	    } elsif ($value !~ /^\./) {  # relative to actual location
		$node->attr($attrib_to_edit,
			    relative_path($fname, normalize_path($base, $node->attr($attrib_to_edit))));
	    }
	}
    }
    
    if ($tag eq 'title' && $startflag) {
	# Replace title
	$node->delete_content();
	$node->push_content($division_info{$relative_current_node}{'title'});
	#print "@@@ TITLE: ", $division_info{$relative_current_node}{'title'}, "\n";
    }
    if ($tag eq 'meta' && $startflag) {
	# Replace META information if available
	my $metatype = $node->attr('name');
	if ($division_info{$relative_current_node}{$metatype}) {
	    $node->attr('content',$division_info{$relative_current_node}{$metatype});
	}
    }

}

sub split_filename {
    # Returns the output filename for a split node.
    my $node = shift;
    my $nodename = $node;
    $nodename =~ s{^/}{};
    return "index.html" if ($nodename eq '');
    if ($division_info{$node}{'children'}) {
	return "$nodename/index.html";
    } else {
	return "$nodename.html";
    }
}

#-------------------
#
# Main program
#
#-------------------

print "AutoSplit Version $version (c) Copyright 2002-2004 wlindley.com, l.l.c.\n";

undef $/;

$base = $ARGV[0]; # First file is actual base, possibly with path

unless (-e $base) {
    die "Cannot open input file '$base'\n";
}
unless (-T $base) {
    die "$base is not a text file.\n";
}

print "Reading $base [$true_base]\n";

open FILE, $base;
$text = <FILE>;
close FILE;

$text =~ s/<![a-zA-Z]+[^>]*>//;  # Remove offensive XML-ish tag foolishness

$orig_text = $text;

do {
    $unique_replace = "~~~" . int(rand(100000)) . "~~~";
} while ($text =~ /$unique_replace/);

print $unique_replace;

$h = new TransientTreeBuilder; 

$h->ignore_unknown(0);
$h->warn(1);
$h->implicit_tags(0);
$h->parse($text);

# split the template into $template_html and all the content into $content_html
$h->traverse(\&make_template);
$template_html = $h->as_HTML();

my $content = new TransientTreeBuilder; 
$content->parse($content_html);
$content->traverse(\&split_content);

{
    # Write the template file, just in case we're interested.
    open FILE, ">" . normalize_path($base, "template.html");
    print FILE $template_html;
    close FILE;
}


foreach my $output_file (keys %division_text) {
    $division_info{$output_file}{'title'} =~ s/[:.]$//; # Remove trailing colon or period from title
#    print "[$output_file]\n";
#    my $fname = normalize_path($base, split_filename($output_file));
    $division_info{$output_file}{'filename'} = 
	normalize_path($base, 
		       $division_info{$output_file}{'split_filename'} =
		       split_filename($output_file));
#    print ">>> $output_file => $division_info{$output_file}{'split_filename'}", 
#	"=> $division_info{$output_file}{'filename'}\n";
}

foreach my $output_file (sort keys %division_text) {
    my $fname = $division_info{$output_file}{'filename'};
    # was: normalize_path($base, split_filename($output_file));

    # Create subdirectories
    # Relies on the nodelist being sorted, so children appear after parents.
    if ($fname =~ m{(.+)/index\.html$}) {
	mkdir $1 unless -d $1;
    }

# for showing bug in Scott's code.
#    my $foo =  $division_text{$output_file};
#    if ($fname eq 'index.html') {
#	print "[", join ' ', map(hex($_), split / */, $foo), "]\n";
#    }

    my $content_text = $division_text{$output_file};
    $content_text =~ s/<\W*>//g;  # remove empty tags.  BUG IN SCOTT'S CODE???
    # add links to children inside page.
    my @kids = @{$division_info{$output_file}{'child_list'}};
    if (scalar @kids) {
	$content_text .= "<BR><UL CLASS='navchildren'>\n";

	my $group;
	foreach my $knode (@kids) {
	    my $title = $division_info{$knode}{'title'};
	    #$content_text .= "<!-- fname = $fname normalize_path = " . normalize_path($base,split_filename($knode)) ." -->\n";
	    # Put simple links here.  They will be made properly relative below.
	    my $link = split_filename($knode);
	    my $relation = $division_info{$output_file}{'is_root'} ? 'chapter' : 'section';
	    if ($division_info{$output_file}{'is_root'}) {
		my $newgroup = $division_info{$knode}{'chapter_group'};
		if ($newgroup ne $group) {
		    $content_text .=  "</div>\n" if ($group);
		    my $title = ($newgroup =~ /^~~/) ? "" : " title='$newgroup'";
		    $content_text .= "<div class='chapter_group'$title>";
		    $group = $newgroup;
		}
	    }
	    $content_text .= "<LI><A HREF=\"$link\" REL=\"$relation\">$title</A></LI>\n";
	}
	$content_text .= "</UL>\n";
    }

    my $output_text = $template_html;
    $output_text =~ s/$unique_replace/$content_text/;
    
    $relative_current_node = $output_file; # ugly global var hack
    my $this_tree = new TransientTreeBuilder; 
    $this_tree->parse($output_text);
    $this_tree->traverse(\&make_links_relative);
    $output_text = $this_tree->as_HTML();
    $this_tree->delete();

    open FILE, ">$fname";
    print "$fname ($output_file)\n";
    print FILE $output_text, "\n";
    close FILE;
}

$h->delete();


__END__;
