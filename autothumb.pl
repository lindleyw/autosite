#!/usr/bin/perl

# makeindex.pl
# 
# 	$Id: makeindex.pl,v 1.2 2003/05/06 15:21:58 bill Exp $
#
# Copyright (c) 2003, wlindley.com, l.l.c.  Scottsdale, AZ  www.wlindley.com
#
# ls *.jpg | ./makeindex.pl -c 3 > index.html
#    makes an index file in 3-column table format,
#    putting thumbnails in the thumb/ directory.
# ls *.jpg | ./makeindex.pl -s -p 65536 > index.html
#    makes an index file in 1-column unordered list format,
#    putting medium-sized pictures of <= 64K pixels in the med/ directory
#    and thumbnails in the thumb/ directory.
#    (Default for -s without -p is equivalent to 640x480)
#
# -t dir/    name thumbnail directory
# -m dir/    name 'medium' image directory
# -c n       set number of columns
# -p n       make 'medium' pictures no larger than 'n' pixels total
# -s         make 'medium' Sized pictures
# -S         make 'medium' Sized pictures for thumbnails, full sized for links
# -T n       limit thumbnails to n-by-n pixels (default: 64)
# -u tfile   use template file and look for text files for each picture.
#            also disables "nnn files, totaling nnn bytes"

#
# index.txt is read, and should be formatted with:
#
#  THUMB:       0 or 1         # whether to produce thumbnails  
#  THUMB.SIZE:  n or  100x100  # sets maximum pixel count, or maximum x,y size 
#  THUMB.DIR:   thumbdir/      # thumbnail directory
#  MEDIUM:      0 or 1         # whether to produce medium size pictures
#  MEDIUM.SIZE: n or  100x100  # sets maximum pixel count, or maximum x,y size
#  MEDIUM.DIR:  meddir/        # medium picture directory
#  LIST.TYPE:                  # 'p' for each image in its own paragraph
#                              # 'table' for multicolumn table
#                              # 'ul' for bulleted text list
#  LIST.COLUMNS: n             # number of columns
#  LIST.IMAGE:                 # 'thumb' for thumbnails
#                              # 'medium' for medium pictures
#  LIST.BORDER:  n             # border size for image list
#  TITLE.IMAGE: filename       # name of image for title.  Will create thumbdir/title.jpg
#                              # As a special case, will also create:
#                              #   thumbdir/title200.jpg   (200x150)
#                              #   thumbdir/title150.jpg   (150x300)
#                              # That behaviour may be generalized in the future.
#  LINKSTYLE:                  # 'medium' for links to medium sized pics
#                              # 'full' for links to full (original) sized pictures
#                              # 'none' for no links at all
#                              # NOTE: if a .txt file exists for an image, that
#                              # overrides 'linkstyle' and a link will be made to
#                              # the page generated by that file and the template.
#  LINK.TARGET  _blank         # to display linked images in a new frame
#  SHOWSIZE:    0 or 1         # enable for "nnn files, totalling nnn bytes" message
#  SHOWNAME:    0 or 1         # enable to display link name in list
#  TEMPLATE:    filename       # path and filename to template file
#  IMAGES:      file,file,...  # list of filenames, or wildcards --   IMAGES: *.jpg

use File::Basename;

use Getopt::Std;
getopt  ('tmc:p:T:u:');

my $pbm = "/usr/local/netpbm/bin/";

unless (-e "${pbm}pnmscale") { $pbm = "/usr/bin/"; }
unless (-e "${pbm}pnmscale") { die "Can't find PBM tools."; }

my $djpeg = "djpeg";
unless (-e "${pbm}$djpeg") { $djpeg = "jpegtopnm"; }
unless (-e "${pbm}$djpeg") { die "Can't locate JPEG-to-PNM"; }
if ($djpeg eq "djpeg") { $djpeg .= ' -ppm ';}  # needs argument

my $cjpeg = "cjpeg";
unless (-e "${pbm}$cjpeg") { $cjpeg = "pnmtojpeg"; }
unless (-e "${pbm}$cjpeg") { die "Can't locate PNM-to-JPEG"; }

my $pamcut = "pamcut";
unless (-e "${pbm}$pamcut") { $pamcut = ''; }   # can't cut images


my $total_files = 0;
my $total_size =0;

my $debug = 1;

my %template_content = ('title' => '', 'contents' => '', 
			'h1' => '', 'h2' => '', 'h2a' => '', 'h3' => '', 'text' => '',
			thumb => 1, 'thumb.size' => '64x64', 'thumb.dir' => 'thumb',
			medium => 0, 'medium.size' => 640*480, 'medium.dir' => 'med',
			'list.type' => 'table', 'list.image' => 'thumb', 'list.columns' => '3',
			'list.border' => 1,
			linkstyle => 'full', 'link.target' => '',
			showsize => 0, showname => 0, images => '*.jpg',
			);

my %index_content = %template_content;

my $template = <<BLORT;
<HTML>
<!-- a basic template -->
<HEAD>
<TITLE>[:title:]</TITLE>
</HEAD>
<BODY>
<h1>[:h1:]</h1>
[:contents:]
</BODY>
</HTML>
BLORT

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
    my @size;

    if (-e $fname) {
	open IMAGE, $fname;
	binmode IMAGE;
	@size = jpegsize() if $fname =~ /\.jpe?g$/i;
	@size = gifsize() if $fname =~ /\.gif$/i;
	close IMAGE;
	return @size;
    } else {
	print STDERR "Image not found: $fname\n";
    }
    return undef;
}

# -----

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

sub add_content {

    $index_content{'contents'} .= shift;

}

sub read_data {
    my $fname = shift;   # first arg is filename to read
    my %content = @_;   # optionally followed by default values (e.g., from main template)

    if (-e $fname) {
	print STDERR "reading $fname\n" if $debug;
	open (TEMPLATE, "<", $fname);
	while (<TEMPLATE>) {
	    my ($key, $value) = /^\s*([\w.]+)\s*:\s*(.*)$/;
	    $key = lc($key);
	    if ($value =~ /<<\s*(\w+)/) { # here-document
		my $stopword = $1;
		$content{$key} = '';
		while (<TEMPLATE>) {
		    last if /$stopword/; # end of here-doc
		    $content{$key} .= $_;
		}
	    } else {
		$content{$key} = $value;
	    }
	}
	close TEMPLATE;
    }
    return (%content);
}

sub replace_content {
    # replace placeholders in template with actual content
    my $output_text = shift;
    my %content = @_;
#    foreach (keys %content) {
#	$output_text =~ s/\[:$_:\]/$content{$_}/gsi;
#    }
    # permit conditionals
    $output_text =~ s/\[:(\w+)\?(\w+):\]/$content{$1}?$content{$1}:$content{$2}/gse;
    # regular text
    $output_text =~ s/\[:(\w+):\]/$content{$1}/gs;
    $output_text =~ s{\s*<h(\d)\b[^>]*>(\s|<br>)*</h\1>}{}gsi; # remove empty header tags
    return $output_text;
}

sub element_html {
    my $tag = shift;
    my %link_attrs = @_;

    my $retval = "<$tag " . join(' ', map {
	my $value = $link_attrs{$_};
	$value ? qq{$_="$value"} : '';
    } keys %link_attrs) . ">";
    return $retval;
}

sub scale_size {
    my $size_spec = shift;
    if ($size_spec =~ /x\s*(\d+)\s*[x|\*](\d+)/i) { # x100x100 = exactly 100x100 (may change aspect ratio)
	return "-xsize $1 -ysize $2 "; 
    } elsif ($size_spec =~ /(\d+)\s*[x|\*](\d+)/) {
	return "-xysize $1 $2 ";
    } else {
	return "-pixels $size_spec";
    }
}

my $b = 1;

sub cutter_command {
    my ($size_spec, $pic_width, $pic_height) = @_;
    return '' unless length($pamcut);
    if  ($size_spec =~ /(\d+)\s*[x|\*](\d+)/) {

	print STDERR "current [$pic_width,$pic_height] ";
	my ($want_x, $want_y) = ($1, $2);
	my ($new_width, $new_height) = ($pic_width, $pic_height);

	my $xratio = $pic_width / $want_x;
	my $yratio = $pic_height / $want_y;
	print STDERR "($xratio, $yratio)\n";
	if ($xratio > $yratio) {
	    # truncate horizontal
	    $new_width = $pic_height / $want_y * $want_x;
	} else {
	    $new_height = $pic_width / $want_x * $want_y;
	}
	print STDERR " new [$new_width, $new_height]", $new_width / $new_height;

	my $xmargin = int($pic_width/2 - $new_width/2) ;
	my $ymargin = int($pic_height/2 - $new_height/2) ;
	print STDERR " margin={$xmargin, $ymargin}";
	# return " ${pbm}$pamcut -width $new_width -height $new_height -verbose | ";
	my $xx = $xmargin ? "-left $xmargin -right -$xmargin" : '';
	my $yy = $ymargin? "-top $ymargin -bottom -$ymargin" : '';
	$b++;
	return " ${pbm}$pamcut $xx $yy -verbose |  ";
    }
    return '';
}

if ($opt_u) {
    open (TEMPLATE, "<", $opt_u);
    $template = '';
    $template .= $_ while (<TEMPLATE>);
    close TEMPLATE;

    # Replace href and src with relative paths
    $template =~ s/\b(href|src)\s*=\s*['"]([^'"]+)['"]/qq{$1="} . relative_path($opt_u, $2) . qq{"}/ge;
    %index_content = read_data('index.txt', %template_content);
}

$template_content{'h1'} = $index_content{'h1'};  # default first header

# override for named thumbnail and medium picture directories
$index_content{'thumb.dir'} = $opt_t if ($opt_t);
unless (-d $index_content{'thumb.dir'}) {
    mkdir ($index_content{'thumb.dir'});
}

if ($opt_m) {
    $index_content{'medium.dir'} = $opt_m;
    $index_content{'medium'} = 1;
}

if ($opt_s) {  # make medium pictures
    $index_content{'medium'} = 1;
    $index_content{'linkstyle'} = 'medium';
}

if ($opt_S) {  # make medium pictures in list, full sized for links
    $index_content{'medium'} = 1;
#    $index_content{'list.type'} = 'table';
    $index_content{'list.image'} = 'medium';
}
if ($opt_p) {
    $index_content{'medium.size'} = $opt_p;
}
if ($opt_c) {
#    $index_content{'list.type'} = 'table';
    $index_content{'list.columns'} = $opt_c;
    $index_content{'showsize'} = 0;
}
if ($opt_T) {
    $index_content{'thumb.size'} = "${opt_T}x${opt_T}";
}

if ($index_content{'medium'}) {
    unless (-d $index_content{'medium.dir'}) {
	mkdir ($index_content{'medium.dir'});
    }
}

my $column = 0;
if ($index_content{'list.type'} eq 'table') {
    add_content ("<TABLE><TR>\n");
} elsif ($index_content{'list.type'} eq 'ul') {
    add_content ("<UL>\n");
}

while (<>) {
    chomp;
    s/\*//;
    my $list_pic;
    my $linked_pic;
    my $link_to;
    my $actual_pic = $_;
    my $linkname_text;
    my $size_text;
    my %link_attrs;

    if (/\.jpe?g$/i) {

	$index_content{'full.name'} = $_;
	my $base_file = $_;
	$base_file =~ s/\.jpe?g//i;
	my $text_file = "${base_file}.txt";
	my $html_file = "${base_file}.html";


	foreach my $pic (qw{medium thumb}) {   # create selected derivative pictures
	    if ($index_content{$pic}) {
		my $picname = $index_content{"${pic}.dir"} . "/$_";
		$index_content{"${pic}.name"} = $picname;
		my $source = $index_content{'full.name'};
		if (($pic eq 'thumb') && ($index_content{'medium'})) {
		    $source = $index_content{"medium.name"};
		}
		my ($width, $height) = image_size ($source);
		# Create derivative picture, unless it exists and is newer than original file.
		unless (-e $picname && -s $picname && ((-M $picname) < (-M $_))) {
		    my $picsize = scale_size($index_content{"${pic}.size"}, $width, $height);
		    print STDERR "creating $picname with: $picsize\n" if $debug;
		    my $cutter = cutter_command($index_content{"${pic}.size"}, $width, $height);
		    my $command = "$pbm$djpeg $source | $cutter ${pbm}pnmscale $picsize | $pbm$cjpeg > $picname";
		    print STDERR $command;
		    system ($command);
		}
	    }
	}

	$list_pic   = $index_content{$index_content{'list.image'} . '.name'};
	$linked_pic = $index_content{$index_content{'linkstyle'} . '.name'};
	$link_to = $linked_pic;   # by default, we link to the picture

	if (-e $text_file) {
	    my %file_content = read_data($text_file, %template_content);

	    $file_content{'contents'} = qq{<IMG SRC="$linked_pic">};
	    $link_attrs{'rel'} = "child";
	    $link_attrs{'title'} = $file_content{'h1'};
	    
	    my $output_text = replace_content($template, %file_content);
	    print STDERR "writing $html_file\n" if $debug;
	    open HTML, ">", $html_file;
	    print HTML $output_text;
	    close HTML;
	    $link_to = $html_file;  # override list's link to be this HTML file.
	}
    }

    if ($index_content{'showsize'}) {
	my $size = -s $linked_pic;
	my $k_size = int(($size + 512) / 1024);
	$total_size += $size;
	$total_files++;
	$size_text = " (${k_size}K)";
    }
    if ($index_content{'showname'}) {
	$linkname_text = "&nbsp;&nbsp;$index_content{'full.name'}"; # link_to";
    }

    $link_attrs{'href'} = $link_to;
    $link_attrs{'target'} = $index_content{'link.target'};
    my $a_text = $link_attrs{'href'} ? element_html('a', %link_attrs) : '';  # optional link
    my $a_end = $a_text ? '</a>' : '';

    my $img_text = element_html('img', src=> $list_pic, border => $index_content{'list.border'});
    my $entry_text = "$a_text$img_text$linkname_text$size_text$a_end";

    if ($index_content{'list.type'} eq 'table') {
	add_content ("<TD align='center' valign='middle'>$entry_text</TD>\n");
	my $new_row = 1;
	if ($index_content{'list.columns'}) {
	    $new_row = 0 if (++$column < $index_content{'list.columns'});
	}
	if ($new_row) {
	    add_content( "</TR>\n<TR>\n");
	    $column = 0;
	}
    } elsif ($index_content{'list.type'} eq 'ul') {
	add_content("<LI>$entry_text</LI>\n");
    } else {
	add_content("<P>$entry_text</P>\n");
    }
}

if ($index_content{'list.type'} eq 'table') {
    add_content ("</TABLE>\n");
} elsif ($index_content{'list.type'} eq 'ul') {
    add_content ("</UL>\n");
}

add_content("$total_files files, totalling $total_size bytes.\n") if ($index_content{'showsize'});

print replace_content($template, %index_content);

exit 1;