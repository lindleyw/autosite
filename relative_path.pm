#
# relative_path.pl
#
# Routines to normalize paths, and to make a path relative from one file to another.
#
#

package Path;

use File::Basename;

sub normalize {
    # INPUTS:
    #  * file location (e.g., an HTML file)
    #  * a path relative to that file.
    # Returns a normalized path.  EXAMPLES:
    # ("P:members\index.htm", "../images/logo.gif") -> 'P:images/logo.gif'
    #	NOTE: the above is actually a relative path on drive P:
    # ("P:\web\members\index.htm", "../images/logo.gif") -> 'P:/web/images/logo.gif'

    my ($base_file, $rel_link) = @_;
    $base_file =~ tr[\\][/];		# use forward slashes
    my ($base_file_name,$base_file_path,$base_file_suffix) = fileparse($base_file,'\..*');

    my $rel_fragment;
    $rel_fragment = $1 if ($rel_link =~ s/(\#\w*$)//); # remove fragment part
    return $rel_fragment unless length($rel_link);  # link was fragment only

    #if (($rel_link =~ /\@/) || ($rel_link !~ /\.\w{3,}/)) {
    #	print "SUSPECT LINK [$rel_link] in $base\n";
    #}

    my ($rel_link_name,$rel_link_path,$rel_link_suffix) = fileparse($rel_link,'\..*');
    $base_file_path =~ tr[\\][/];		# use forward slashes (again, after fileparse)
    $rel_link_name =~ tr[\\][/];
    # Append path, unless relative to current directory:
    $base_file_path .= $rel_link_path unless ($rel_link_path =~ m{^\.[\\\/]$});

    # Resolve '../' relative paths
    while ($base_file_path =~ s[[\w\-]+./\.\./][]g) {};
    # Concatenate path, name, and suffix
    $rel_link = $base_file_path . $rel_link_name . $rel_link_suffix . $rel_fragment;
    $rel_link =~ s[/\./][/]g;           # also change any "xyz/./foo"  to "xyz/foo"
    $rel_link =~ s[^\./][];		# current directory is implied!
#    print "NAME = $base_file_name\nPATH = $base_file_path\nSUFFIX = $base_file_suffix\n";
#    print "-----> $rel_link\n";
    return $rel_link;
}

sub relative {
    # Basically the inverse of normalize_path.
    # Accepts two paths, and returns a relative path
    # from the first to the second.
    my ($from_file, $to_file) = @_;
    my $relative_path='';
    
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

1;
