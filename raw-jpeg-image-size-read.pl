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
    if (exists $file_info{$fname} && exists $file_info{$fname}{'width'}) {
	return ($file_info{$fname}{'width'},$file_info{$fname}{'height'});
    }
    my $true_fname = $fname; # true_location($fname);
    my @size;
    if (-e $true_fname) {
	open IMAGE, $true_fname;
	binmode IMAGE;
#	my $bytesread = read(IMAGE, my $gif_header, 12);
	@size = jpegsize() if $fname =~ /\.jpe?g$/i;
	@size = gifsize() if $fname =~ /\.gif$/i;
	close IMAGE;
	return @size;
#	return undef unless ($bytesread == 12);
#	my ($id, $width, $height) = unpack ("a6vv",$gif_header);
#	return undef unless ($id eq "GIF89a");
#	($file_info{$fname}{'width'},$file_info{$fname}{'height'}) = ($width, $height);
#	return ($width, $height);
    }
    return undef;
}

print join(',',image_size('test.jpg'));
