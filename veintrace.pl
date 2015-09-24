#!/bin/env perl
use strict;
use warnings 'FATAL' => 'all';
use Imager;
use DataBrowser;

## GLOBALS ##

my $SCALE = 3;
my $MAXRES = 3;
my $WHITEISH = 50; # threshold for image whiteness

## Command Line ##

die "usage: veintrace.pl <image_file>\n" unless @ARGV == 1;
my ($bmp) = @ARGV;

## Read bmp and save in several reduced resolutions ##
print STDERR "reading";
my @img;
$img[$MAXRES] = Imager->new;
$img[$MAXRES]->read(file => $bmp) or die "Cannot read $bmp: ", Imager->errstr;
for (my $i = $MAXRES-1; $i >= 0; $i--) {
	print STDERR ".";
	$img[$i] = $img[$i+1]->scale(scalefactor => 1/$SCALE);
}
print STDERR "done\n";

## Find Origin ##
my $origin = find_origin($img[0], 10, 8, 4, 11); # step, hlen, tlen, gutter
my $i0 = $img[0]->copy();
plot_seg($i0, $origin);		
$i0->write(file=>"origin.png") or die Imager->errstr;

## Primary ##
my $primary = trace_seg($img[0], $origin, 10, 5, 10);
my $i1 = $img[0]->copy();
foreach my $point (@$primary) {
	my ($x, $y) = @$point;
	$i1->setpixel('x'=>$x, 'y'=>$y, color=>'red');
}
$i1->write(file=>"primary.png") or die Imager->errstr;

=debug

my $n = 0;
foreach my $unit (@$primary) {
	$n++;
	print_seg($unit);
	my $im = $img[0]->copy();
	plot_seg($im, $unit);
	my $string = '0' x (3 - length($n)) . $n;
	$im->write(file=>"primary-$string.png") or die Imager->errstr;
}

=cut

## Secondary ##
print STDERR "finding secondary origins...";
my $xa = 60; # excluded angle from main vein (front)
my $xb = 60; # excluded angle (back)
my $step = 10;
my @angle;
for (my $angle = -$xb; $angle <= -$xa; $angle += $step) {push @angle, $angle}
for (my $angle =  $xa; $angle <=  $xb; $angle += $step) {push @angle, $angle}

my $len = 10;
my @pool;
foreach my $seg (@$primary) {
	my ($x0, $y0, $a0) = @$seg;
	$x0 *= $SCALE;
	$y0 *= $SCALE;
	foreach my $angle (@angle) {
		my $base = [$x0, $y0, $a0 + $angle, $len];
		my ($hinge, $score) = best_hinge($img[1], $base, 15, 5); # arc, step
		push @pool, {hinge => $hinge, score => $score};
	}
}
@pool = sort {$b->{score} <=> $a->{score}} @pool;

my $exlude = 20;
my @ori2;
while (@pool) {
	my $ori2 = shift @pool;
	push @ori2, $ori2;
	my ($x0, $y0) = @{$ori2->{hinge}[0]};
	my @keep;
	foreach my $truc (@pool) {
		my ($x1, $y1) = @{$truc->{hinge}[0]};
		if (distance($x0, $y0, $x1, $y1) > $exlude) {
			push @keep, $truc;
		}
	}
	@pool = @keep;
}

# secondary vein origins
my $i2 = $img[1]->copy();
foreach my $truc (@ori2) {
	plot_hinge($i2, $truc->{hinge});
}
$i2->write(file=>"secondary_origin.png") or die Imager->errstr;
print STDERR "done\n";

#############################################################################
# Functions
#############################################################################


sub next_seg {
	my ($img, $ori, $arc, $step, $len) = @_;

	# find the 3 starting positions
	my ($x0, $y0, $a0) = @$ori;
	my ($x1, $y1) = @{head($ori)};
	my $d0 = distance($x0, $y0, $x1, $y1);
	my @start; # 3 possible starts
	for (my $i = -1; $i <= 1; $i++) {
		for (my $j = -1; $j <= 1; $j++) {
			next if $i == 0 and $j == 0;
			my $x = $x0 + $i;
			my $y = $y0 + $j;
			my $d = distance($x, $y, $x1, $y1);
			push @start, [$x, $y] if $d < $d0;
		}
	}
	
	# find optimal (x, y, angle) for each start
	my $aMin = $a0 - $arc;
	my $aMax = $a0 + $arc;
	my $max_score = 0;
	my $opt_seg;
	foreach my $start (@start) {
		my ($nx0, $ny0, $nx1, $ny1, $na0);
		for (my $angle = $aMin; $angle <= $aMax; $angle += $step) {
			my $seg = [@$start, $angle, $len];
			my $score = score_seg($img, $seg);
			if ($score > $max_score) {
				$max_score = $score;
				$opt_seg = $seg;
			}
		}
	}
		
	return $opt_seg, $max_score;
}

sub best_hinge {
	my ($img, $ori, $arc, $step) = @_;
			
	my ($x0, $y0, $a0, $len) = @$ori;
	
	my @pool;
	for (my $a1 = $a0 - $arc; $a1 <= $a0 + $arc; $a1 += $step) {
		my $seg1 = [$x0, $y0, $a1, $len];
		my $score1 = score_seg($img, $seg1);
		my $head = head($seg1);
		my ($x1, $y1) = @$head;
		for (my $a2 = $a1 - $arc; $a2 <= $a1 + $arc; $a2 += $step) {
			my $seg2 = [$x1, $y1, $a2, $len];
			my $score2 = score_seg($img, $seg2);
			push @pool, {
				score => ($score1 + $score2) / 2,
				hinge => [$seg1, $seg2],
			};
		}
	}
	
	@pool = sort {$b->{score} <=> $a->{score}} @pool;
	return $pool[0]{hinge}, $pool[0]{score};
}



sub trace_seg {
	my ($img, $seg0, $arc, $step, $len, $plan) = @_;
	
	my $xlimit = $img->getwidth();
	my $ylimit = $img->getheight();
	print STDERR "tracing segments in ($xlimit x $ylimit)\n";
	
	my $seg = [@$seg0];
	my %seen;
	my $path;
	while (1) {
		my $t = threshold($img, $seg, $arc, $step);
		my ($next, $score) = next_seg($img, $seg, $arc, $step, $len);
		if ($score > $t) {
			my $s = "$next->[0],$next->[1]";
			if ($seen{$s}) {
				warn "collision at $s $next->[2]°\n";
				last;
			}
			else {
				$seen{$s} = 1;
			}
			push @$path, $next;
			$seg = $next;
		} else {
			last;
		}	
	}
	
	return $path;
}

sub trace_hinge {
	my ($img, $seg0, $arc, $step, $len, $plan) = @_;
	
	my $xlimit = $img->getwidth();
	my $ylimit = $img->getheight();
	print STDERR "tracing segments in ($xlimit x $ylimit)\n";
	
	my $seg = [@$seg0];
	my %seen;
	my $path;
	while (1) {
		my $t = 150; #threshold($img, $seg, $arc, $step);
		my ($next, $score) = next_seg($img, $seg, $arc, $step, $len);
		if ($score > $t) {
			my $s = "$next->[0],$next->[1]";
			if ($seen{$s}) {
				warn "collision at $s $next->[2]°\n";
				last;
			}
			else {
				$seen{$s} = 1;
			}
			push @$path, $next;
			$seg = $next;
		} else {
			last;
		}	
	}
	
	return $path;
}



sub plot_hinge {
	my ($img, $hinge) = @_;
	my ($s1, $s2) = @$hinge;
	
	my $p1 = points_in_seg($s1);
	my $p2 = points_in_seg($s2);
	
	foreach my $point (@$p1) {
		my ($x, $y) = @$point;
		$img->setpixel('x'=>$x, 'y'=>$y, color=>'red');
	}
	foreach my $point (@$p2) {
		my ($x, $y) = @$point;
		$img->setpixel('x'=>$x, 'y'=>$y, color=>'green');
	}
}

## Scoring functions

sub score_point {
	my ($img, $point) = @_;
	my ($x, $y) = @$point;
	my $pixel = $img->getpixel('x' => $x, 'y' => $y);
	if (defined $pixel) {
		my ($val) = $pixel->rgba;
		return 255 - $val;
	} else {
		die "undefined value at $x,$y";
	}
}

sub threshold {
	my ($img, $seg, $arc, $step) = @_;
	my ($x0, $y0, $a0, $l0) = @$seg;
	my %point;
	for (my $angle = $a0 - $arc; $angle < $a0 + $arc; $angle += $step) {
		my $ttt = [$x0, $y0, $angle, $l0];
		my $points = points_in_seg($ttt);
		foreach my $point (@$points) {
			my ($x, $y) = @$point;
			$point{"$x,$y"} = 1;
		}
	}
	my @score;
	foreach my $coor (keys %point) {
		my ($x, $y) = split(/,/, $coor);
		push @score, score_point($img, [$x, $y]);
	}
	@score = sort {$b <=> $a} @score;
		
	my $t = $score[@score * 0.8];
	if ($t < $WHITEISH) {return 255}
	else {return $t}
}

## Graphing / text functions

sub print_seg {
	my ($seg, $score) = @_;
	$score = 0 if not defined $score;
	printf "%d,%d %d° %d %d\n", @$seg, $score;
}

sub plot_seg {
	my ($img, $seg) = @_;
	my $hp = points_in_seg($seg);
	foreach my $point (@$hp) {
		my ($x, $y) = @$point;
		$img->setpixel('x'=>$x, 'y'=>$y, color=>'green');
	}
	$img->setpixel('x'=>$seg->[0], 'y'=>$seg->[1], color=>'red');
}


## Scoring functions

sub score_seg {
	my ($img, $seg) = @_;
	my $sum = 0;
	my $points = points_in_seg($seg);
	foreach my $point (@$points) {
		$sum += score_point($img, $point);
	}
	return int $sum / @$points;
}

## Segment basic functions

sub points_in_seg {
	my ($seg) = @_;
	my ($x0, $y0) = @$seg;
	my $head = head($seg);
	my ($x1, $y1) = @$head;
	my $points = points_on_line($x0, $y0, $x1, $y1);
}

sub head {
	my ($seg) = @_;
	my ($x0, $y0, $a0, $h0) = @$seg;
	my $rad = 2 * 3.14159 * $a0 / 360;
	my $x1 = $x0 + cos($rad) * $h0;
	my $y1 = $y0 + sin($rad) * $h0;
	$x1 = int($x1 + 0.5);
	$y1 = int($y1 + 0.5);	
	return [$x1, $y1];
}

## Basic graphing functions

sub angle {
	my ($x0, $y0, $x1, $y1) = @_;
	my $dx = $x1 - $x0;
	my $dy = $y1 - $y0;
	my $angle = atan2($dy, $dx);
	my $degrees = 360 * $angle / (2 * 3.1415); # -180 to 180
	return int($degrees + 0.5);
}

sub distance {
	my ($x0, $y0, $x1, $y1) = @_;
	return sqrt(($x0-$x1)**2 + ($y0-$y1)**2);
}

sub points_on_line {
	my ($x0, $y0, $x1, $y1, $mode) = @_;
	
	# round off values
	$x0 = int($x0 + 0.5);
	$y0 = int($y0 + 0.5);
	$x1 = int($x1 + 0.5);
	$y1 = int($y1 + 0.5);
	
	my @point; # non-redundant points on the line
	
	if ($x0 == $x1) { # check for vertical lines first
		if ($y0 == $y1) {
			push @point, [$x0, $y0];
		} elsif ($y0 < $y1) {
			for (my $y = $y0; $y <= $y1; $y++) {
				push @point, [$x0, $y];
			}
		} else {
			for (my $y = $y0; $y >= $y1; $y--) {
				push @point, [$x0, $y];
			}	
		}
	} else { # Bresenham's algorithm for line tracing
		my %check;
		my $dx = $x1 - $x0;
		my $dy = $y1 - $y0;
		my $error = 0;
		my $derror = abs($dy/$dx);
		my $y = $y0;
		
		if ($x0 < $x1) {
			for (my $x = $x0; $x <= $x1; $x++) {
				if (not defined $check{"$x,$y"}) {
					$check{"$x,$y"} = 1;
					push @point, [$x, $y];
				}
				$error += $derror;
				while ($error >= 0.5) {
					last if $x == $x1 and $y == $y1;
					if (not defined $check{"$x,$y"}) {
						$check{"$x,$y"} = 1;
						push @point, [$x, $y];
					}
					$y += $y1 > $y0 ? +1 : -1;
					$error -= 1.0;
				}
			}
		} else {
			for (my $x = $x0; $x >= $x1; $x--) {
				if (not defined $check{"$x,$y"}) {
					push @point, [$x, $y];
					$check{"$x,$y"} = 1;
				}
				$error += $derror;
				while ($error >= 0.5) {
					last if $x == $x1 and $y == $y1;
					if (not defined $check{"$x,$y"}) {
						push @point, [$x, $y];
						$check{"$x,$y"} = 1;
					}
					$y += $y1 > $y0 ? +1 : -1;
					$error -= 1.0;
				}
			}
		}
	}
	
	shift @point if defined $mode and $mode eq '-ori';
	return \@point;
}

## Origin functions

sub find_origin {
	my ($img, $step, $hlen, $tlen, $gutter) = @_;
	
	my $ORIGINS = 100; # number of origins to consider

	my $xlimit = $img->getwidth();
	my $ylimit = $img->getheight();
	print STDERR "finding origins in ($xlimit x $ylimit)\n";
	
	# look for darkest blobs
	my @blob;
	for (my $x = $gutter; $x < $xlimit -$gutter; $x++) {
		for (my $y = $gutter; $y < $ylimit - $gutter; $y++) {
			my $score = _score_blob($img, $x, $y);
			push @blob, {
				point => [$x, $y],
				score => $score,
			}
		}
		@blob = sort {$b->{score} <=> $a->{score}} @blob;
		splice(@blob, $ORIGINS);
	}
			
	# identify origin as segment & following white-space
	my ($cx, $cy) = ($xlimit/2, $ylimit/2); # center of image
	my $origin;
	my $max_score = 0;
	foreach my $item (@blob) {
		my ($x0, $y0) = @{$item->{point}};
		my $ta = angle($x0, $y0, $cx, $cy);
		my $ca = $ta + 180;
		my $a1 = $ta - 45;
		my $a2 = $ta + 45;
		
		for (my $angle = $a1; $angle < $a2; $angle += $step) {
			my $head = [$x0, $y0, $angle, $hlen];
			my $tail = [$x0, $y0, $angle+180, $tlen];
			my $hscore = score_seg($img, $head);
			my $tscore = score_seg($img, $tail);
			my $score = $hscore - $tscore;
			
			if ($score > $max_score) {
				$origin = [$x0, $y0, $angle, $hlen];
				$max_score = $score;
			}
		}
	}
		
	return $origin;
}

sub _score_blob {
	my ($img, $x0, $y0) = @_;
		
	my @blob = (
		[ 0, -2],
		[-1, -1],      #
		[ 0, -1],     ###
		[ 1, -1],    #####
		[-2,  0],     ###
		[-1,  0],      #
		[ 0,  0],
		[ 1,  0],
		[ 2,  0],
		[-1,  1],
		[ 0,  1],
		[ 1,  1],
		[ 0,  2],
	);
	
	my $score = 0;
	foreach my $point (@blob) {
		my $ix = $x0 + $point->[0];
		my $iy = $y0 + $point->[1];
		$score += score_point($img, [$ix, $iy]);
	}
	
	return $score;
}



__END__

# Data Types #

A $point is a 2-part structure x,y coordinate pair held as an array
reference. A @point is considered an unordered collection. $points is
the preferred name for a reference to @point.

A $unit is a 5-part structure that contains x, y, angle, head-length,
and tail-length. The x,y point is considered the MIDDLE of the unit with
a head and tail extending in opposite directions. The angle is the
direction of the HEAD. A @unit is considered an unordered collection and
$units is the preferred name for a reference of @unit.

A $path is an ordered array of $unit. In the case of primary veins,
there is only one $path. Secondary and tertiary $path arrays can be
collected into $paths.

A $seg (segment) is a line segment with 4 parts: x, y, angle, length.

A $hinge is an array of 2 segments.

A $spine is an ordered set of line segments with a maximum angle slop. This
is stored as an array reference with [slop, seg, seg, seg]. Typical usage
is like my ($slop, @seg) = @$spine;



----

A $surface is a collection of $unit stored in a 2-dimensional hash
reference in which the x and y coordinates are the hash keys. This
prevents unit collision on the surface.

A $graph is an array of $surface whose indices correspond to different
image resolutions.

An $image is an array of Imager objects indexed identically to a
$graph. The highest resolution image is at index 0.




=debug

my $t2 = 20; # distance threshold
my $t3 = 60; # angle threshold
my @branch;
while (@pool) {
	my $best = shift @pool;
	my $conflict = 0;
	foreach my $branch (@branch) {
		my ($x0, $y0, $a0) = @{$best->{seg}};
		my ($x1, $y1, $a1) = @$branch;
		if (distance($x0, $y0, $x1, $y1) < $t2 and abs($a0 - $a1) < $t3) {
			$conflict = 1;
			last;
		}
	}
	push @branch, $best->{seg} unless $conflict;
}
print STDERR "done\n";
print scalar @branch, " branches...\n";

#print STDERR "tracing secondary veins...";
#my $secondary;
#foreach my $branch (@branch) {
#	my ($x0, $y0, $a0) = @$branch;
#	my $start = [$x0, $y0, $a0, 9, 3]; # should be scaled up
#	my $vein = trace_vein($img[1], $start, 30, 5, 9, 3);
#	push @$secondary, $vein;
#}
#print STDERR "done\n";

=cut

=old

print STDERR "finding secondary origins...";
my @pool;
my $s1 = 5; # degrees per step for secondary origins
my $h1 = 10; # head length
my $t1 = 0; # tail length
my $xa = 40; # excluded angle from main vein (front)
my $xb = 60; # excluded angle (back)

my @angle;
for (my $angle = -$xb; $angle <= -$xa; $angle += $s1) {push @angle, $angle}
for (my $angle =  $xa; $angle <=  $xb; $angle += $s1) {push @angle, $angle}

foreach my $unit (@$primary) {
	my ($x0, $y0, $a0) = @$unit;
	$x0 *= 3;
	$y0 *= 3;
	foreach my $angle (@angle) {
		my $unit = [$x0, $y0, $a0 + $angle, $h1, $t1];
		my $score = score_unit($img[1], $unit);
		if ($score > 150) {
			push @pool, {score => $score, unit => $unit};
		}	
	}
}
@pool = sort {$b->{score} <=> $a->{score}} @pool;



my $t2 = 20; # distance threshold
my $t3 = 60; # angle threshold
my @branch;
while (@pool) {
	my $best = shift @pool;
	my $conflict = 0;
	foreach my $branch (@branch) {
		my ($x0, $y0, $a0) = @{$best->{unit}};
		my ($x1, $y1, $a1) = @$branch;
		if (distance($x0, $y0, $x1, $y1) < $t2 and abs($a0 - $a1) < $t3) {
			$conflict = 1;
			last;
		}
	}
	push @branch, $best->{unit} unless $conflict;
}
print STDERR "done\n";
print scalar @branch, " branches...\n";

print STDERR "tracing secondary veins...";
my $secondary;
foreach my $branch (@branch) {
	my ($x0, $y0, $a0) = @$branch;
	my $start = [$x0, $y0, $a0, 9, 3]; # should be scaled up
	my $vein = trace_vein($img[1], $start, 30, 5, 9, 3);
	push @$secondary, $vein;
}
print STDERR "done\n";


=cut


###################
# Testing Section #
###################

if ($opt_t) {

	print STDERR "running tests...";



#	my $i3 = $img[1]->copy();
#	foreach my $vein (@$secondary) {
#		foreach my $unit (@$vein) {
#			my ($px, $py) = @$unit;
#			$i3->setpixel('x'=>$px, 'y'=>$py, color=>'red');
#		}
#	}
#	$i3->write(file=>"secondary.png") or die Imager->errstr;

	
	print STDERR "done\n";
}


sub _perps {
	my ($x, $y, $angle, $w) = @_;
		
	my $r90 = 3.1415926 / 2;
	my $x0 = int(0.5 + $x + cos($angle + $r90) * $w / 2);
	my $y0 = int(0.5 + $y + sin($angle + $r90) * $w / 2);
	my $x1 = int(0.5 + $x + cos($angle - $r90) * $w / 2);
	my $y1 = int(0.5 + $y + sin($angle - $r90) * $w / 2);

	return $x0, $y0, $x1, $y1;
}