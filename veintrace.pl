#!/bin/env perl
use strict;
use warnings 'FATAL' => 'all';
use Imager;
use DataBrowser;
use Getopt::Std;
use vars qw($opt_s $opt_r $opt_0 $opt_1 $opt_2 $opt_3 $opt_t);
getopts('s:r:0:1:2:3:t');

## GLOBALS ##

my $SCALE   = 3;
my $MAX_RES = 3;
my $RES_0   = 3;
my $RES_1   = 2;
my $RES_2   = 1;
my $RES_3   = 0;
my $TEST    = 0;

## Command Line ##

die "
usage: veintrace.pl [options] <image_file>
  -s <int>    scale [$SCALE]
  -r <int>    maximum resolution [$MAX_RES]
  -0 <int>    origin resolution [$RES_0]
  -1 <int>    primary vein resolution [$RES_1]
  -2 <int>    secondary vein resolution [$RES_2]
  -3 <int>    tertiary vein resolution [$RES_3]
  -t          test mode
" unless @ARGV == 1;
my ($bmp) = @ARGV;

$SCALE   = $opt_s if $opt_s;
$MAX_RES = $opt_r if $opt_r;
$RES_0   = $opt_0 if $opt_0;
$RES_1   = $opt_1 if $opt_1;
$RES_2   = $opt_2 if $opt_2;
$RES_3   = $opt_3 if $opt_3;
$TEST    = $opt_t if $opt_t;

## Read bmp and save in several reduced resolutions ##

print STDERR "reading";
my @IMAGE;
$IMAGE[0] = Imager->new;
$IMAGE[0]->read(file => $bmp) or die "Cannot read $bmp: ", Imager->errstr;
for (my $i = 1; $i <= $MAX_RES; $i++) {
	print STDERR ".";
	$IMAGE[$i] = $IMAGE[$i-1]->scale(scalefactor => 1/$SCALE);
}
print STDERR "done\n";

## Find Origin ##
my $s0 = 10; # 10 degrees per step for origin
my $h0 = 15; # 15 pixel head length
my $t0 =  5; # 5 pixel tail length
my $g0 = 16; # 16 pixel image gutter
my $origin = find_origin($IMAGE[$RES_0], $s0, $h0, $t0, $g0);

## Trace Main Vein ##
my $a1 = 20; # arc degrees
my $s1 = 5;  # degrees per step
my $h1 = 5; # head length
my $t1 = 5; # tail length

my @primary;
my $unit = $origin;
my $count = 0;
my %seen;
#print STDERR "tracing primary vein";
while (1) {
#	print STDERR ".";
	my $t = threshold($IMAGE[$RES_0], $unit, $a1, $s1);
	my ($next, $score) = next_unit($IMAGE[$RES_0], $unit, $a1, $h1, $t1, $s1);
		
	if ($score < $t) {
		my $s = "$next->[0],$next->[1]";
		if ($seen{$s}) {
			warn "endless loop at $s $next->[2]°\n";
			last;
		}
		else {
			$seen{$s} = 1;
		}
		push @primary, $next;
		$unit = $next;
	} else {
		last;
	}	
}
#print STDERR "\n";

###################
# Testing Section #
###################

if ($TEST) {

	# origin
	my $i0 = $IMAGE[$RES_0]->copy();
	my ($x0, $y0, $a0, $h0, $t0) = @$origin;
	$i0->circle(color => 'green', 'x'=>$x0, 'y'=>$y0, 'r'=>3);
	my ($x1, $y1) = @{head($origin)};
	my $points = points_on_line($x0, $y0, $x1, $y1);
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		$i0->setpixel('x'=>$x, 'y'=>$y, color=>'red');
	}		
	$i0->write(file=>"origin.png") or die Imager->errstr;	
		
	# primary vein	
	my $i1 = $IMAGE[$RES_0]->copy();
	foreach my $unit (@primary) {
		my ($x, $y) = @$unit;
		$i1->setpixel('x'=>$x, 'y'=>$y, color=>'red');
	}
	$i1->write(file=>"primary.png") or die Imager->errstr;

	# all paths on the primary vein	
	for (my $i = 0; $i < @primary; $i++) {
		my $img = $IMAGE[$RES_0]->copy();
		plot_unit($img, $primary[$i]);
		my $n = '0' x (3 - length($i));
		my $name = "primary-$n$i.png";
		$img->write(file=>"$name") or die Imager->errstr;
	}
	die "testing primary";
}

#############################################################################
# Functions
#############################################################################

sub angle {
	my ($x0, $y0, $x1, $y1) = @_;
	my $dx = $x1 - $x0;
	my $dy = $y1 - $y0;
	my $angle = atan2($dy, $dx);
	my $degrees = 360 * $angle / (2 * 3.1415); # -180 to 180
	return int($degrees + 0.5);
}

sub head {
	my ($unit) = @_;
	my ($x0, $y0, $a0, $h0, $t0) = @$unit;
	my $rad = 2 * 3.14159 * $a0 / 360;
	my $x1 = $x0 + cos($rad) * $h0;
	my $y1 = $y0 + sin($rad) * $h0;
	$x1 = int($x1 + 0.5);
	$y1 = int($y1 + 0.5);	
	return [$x1, $y1];
}

sub tail {
	my ($unit) = @_;
	my ($x0, $y0, $a0, $h0, $t0) = @$unit;
	$a0 += 180;
	my $rad = 2 * 3.14159 * $a0 / 360;
	my $x1 = $x0 + cos($rad) * $t0;
	my $y1 = $y0 + sin($rad) * $t0;
	$x1 = int($x1 + 0.5);
	$y1 = int($y1 + 0.5);	
	return [$x1, $y1];
}

sub points_in_head {
	my ($unit) = @_;
	my ($x0, $y0) = @$unit;
	my $head = head($unit);
	my ($x1, $y1) = @$head;
	my $points = points_on_line($x0, $y0, $x1, $y1, '-ori');
}

sub points_in_tail {
	my ($unit) = @_;
	my ($x0, $y0) = @$unit;
	my $tail = tail($unit);
	my ($x1, $y1) = @$tail;
	my $points = points_on_line($x0, $y0, $x1, $y1, '-ori');
}

sub points_in_unit {
	my ($unit) = @_;
	my $origin = [$unit->[0], $unit->[1]];
	my $head_points = points_in_head($unit);
	my $tail_points = points_in_tail($unit);
	return [$origin, @$head_points, @$tail_points];
}

sub points_on_line {
	my ($x0, $y0, $x1, $y1, $mode) = @_;
	
	# round off values
	$x0 = int($x0 + 0.5);
	$y0 = int($y0 + 0.5);
	$x1 = int($x1 + 0.5);
	$y1 = int($y1 + 0.5);
	
	my %point; # non-redundant collection of all points on the line
	
	# check for vertical lines first
	my $score = 0;
	if ($x0 == $x1) {
		my @point;
		($y0, $y1) = ($y1, $y0) if $y0 > $y1;
		for (my $y = $y0; $y <= $y1; $y++) {
			push @point, [$x0, $y];
		}
		return \@point;	
	}
	
	# swap coordinates for 'left' side of graph
	if ($x0 > $x1) {
		($x0, $x1) = ($x1, $x0);
		($y0, $y1) = ($y1, $y0);
	}

	# Bresenham's algorithm for line tracing
	my $dx = $x1 - $x0;
	my $dy = $y1 - $y0;
	my $error = 0;
	my $derror = abs($dy/$dx);
	my $y = $y0;
	for (my $x = $x0; $x <= $x1; $x++) {
		$point{"$x,$y"} = 1;
		$error += $derror;
		while ($error >= 0.5) {
			last if $x == $x1 and $y == $y1;
			$point{"$x,$y"} = 1;
			$y += $y1 > $y0 ? +1 : -1;
			$error -= 1.0;
		}
	}
	
	delete $point{"$x0,$y0"} if defined $mode and $mode eq '-ori';
		
	# return as array of (x,y) pairs
	my @point;
	foreach my $point (keys %point) {
		my ($x, $y) = split(",", $point);
		push @point, [$x, $y];
	}
		
	return \@point;
}

sub next_unit {
	my ($img, $ori, $arc, $hlen, $tlen, $step) = @_;

	my ($x0, $y0, $a0) = @$ori;
	my $aMin = $a0 - $arc;
	my $aMax = $a0 + $arc;
	
	# find optimal angle from here
	print "angle in $a0\n";
	my $min_score = 1e30;
	my $opt_angle;
	for (my $angle = $aMin; $angle <= $aMax; $angle += $step) {
		my $unit = [$x0, $y0, $angle, $hlen, $tlen];
		my $score = score_unit($img, $unit);
		print "\t$angle° $score\n";
		if ($score < $min_score) {
			$min_score = $score;
			$opt_angle = $angle;
		}
	}
	print "angle out $opt_angle, score $min_score\n";
	
	# find nearest pixel on line
	my $best = [$x0, $y0, $opt_angle, $hlen, $tlen];
	my $points = points_in_head($best);
	my ($next_x, $next_y);
	foreach my $point (@$points) {
		my ($x1, $y1) = @$point;
		next if $x1 == $x0 and $y1 == $y0;
		next if abs($x0 - $x1) > 1 or abs($y0 - $y1) > 1;
		$next_x = $x1;
		$next_y = $y1;
	}
	
	my $next_unit = [$next_x, $next_y, $opt_angle, $hlen, $tlen];
	print_unit($next_unit);
	
	return $next_unit, $min_score;
}

sub threshold {
	return 220; # temporary


	my ($img, $unit, $arc, $step) = @_;
	my ($x0, $y0, $a0, $len) = @$unit;
	my %point;
	for (my $angle = $a0 - $arc; $angle <= $a0 + $arc; $angle += $step) {
		my $points = points_on_line([$x0, $y0, $angle, $len]);
		foreach my $point (@$points) {
			my $coor = "$point->[0],$point->[1]";
			$point{$coor}++;
		}
	}
	
	my @val;
	foreach my $coor (keys %point) {
		my ($x, $y) = split(/,/, $coor);
		my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
		push @val, $val;
	}
	@val = sort {$a <=> $b} @val;
	my $t = $val[@val / 2]; # to be reconsidered
	
	return $t;
}


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
		@blob = sort {$a->{score} <=> $b->{score}} @blob;
		splice(@blob, $ORIGINS);
	}
			
	# identify origin as dark line & light line opposite
	# with a path leading to the long side of the image
	my ($cx, $cy) = ($xlimit/2, $ylimit/2); # center of image
	my $origin;
	my $min_score = 1e30;
	foreach my $item (@blob) {
		my ($x0, $y0) = @{$item->{point}};
		my $ta = angle($x0, $y0, $cx, $cy);
		my $ca = $ta + 180;
		my $a1 = $ta - 45;
		my $a2 = $ta + 45;
		
		for (my $angle = $a1; $angle < $a2; $angle += $step) {
			my $unit = [$x0, $y0, $angle, $hlen, $tlen];
			my $head = head($unit);
			my $tail = tail($unit);
			my $p1 = points_on_line($x0, $y0, @$head);
			my $p2 = points_on_line($x0, $y0, @$tail, '-ori');
			my $score;
			foreach my $p (@$p1) {
				my ($x, $y) = @$p;
				my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
				$score += $val;
			}
			foreach my $p (@$p2) {
				my ($x, $y) = @$p;
				my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
				$score -= $val;
			}
			if ($score < $min_score) {
				$origin = [$x0, $y0, $angle, $hlen, $tlen];
				$min_score = $score;
			}
		}
	}
		
	return $origin;
}

sub score_unit {
	my ($img, $unit) = @_;
	
	my $sum = 0;
	my $points = points_in_unit($unit);
#	my @sum;
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
		$sum += $val;
#		push @sum, $val;
	}
#	print "\t@sum\n";
	
	return int $sum / @$points;
}

sub plot_unit {
	my ($img, $unit) = @_;
	my $hp = points_in_head($unit);
	foreach my $point (@$hp) {
		my ($x, $y) = @$point;
		$img->setpixel('x'=>$x, 'y'=>$y, color=>'green');
	}
	my $tp = points_in_tail($unit);
	foreach my $point (@$tp) {
		my ($x, $y) = @$point;
		$img->setpixel('x'=>$x, 'y'=>$y, color=>'red');
	}
	$img->setpixel('x'=>$unit->[0], 'y'=>$unit->[1], color=>'blue');
}

sub print_unit {
	my ($unit) = @_;
	printf "%d,%d %d° %d %d\n", @$unit;
}

########################
# Single-use Functions #
########################

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
		my ($val) = $img->getpixel('x' => $ix, 'y' => $iy)->rgba;
		$score += $val;
	}
	
	return $score;
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

A $surface' is a collection of $unit stored in a 2-dimensional hash
reference in which the x and y coordinates are the hash keys. This
prevents unit collision on the surface.

A $graph is an array of $surface whose indices correspond to different
image resolutions.

An $image is an array of Imager objects indexed identically to a
$graph. The highest resolution image is at index 0.

