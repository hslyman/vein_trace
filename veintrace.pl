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
my $l0 = 15; # 20 pixel origin length
my $g0 = 16; # 21 pixel image gutter
my $origin = find_origin($IMAGE[$RES_0], $s0, $l0,  $g0);

## Trace Main Vein ##
my $a1 = 15; # 30 degree arc allowed
my $s1 = 5; # 5 degrees per step
my $l1 = 5; # 5 pixel unit length

my $unit = $origin;
my @primary;
my $count = 0;
my %seen;
while ($unit) {
	
	my $t = threshold($IMAGE[$RES_0], $unit, $a1, $s1);
	my ($next, $score) = next_unit($IMAGE[$RES_0], $unit, $a1, $l1, $s1);
	
	print_unit($unit, $score, $t);
	
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
		$unit = 0;
	}	
}

# hitting endless loops on t5 and t8
# getting some kind of stable flip-flop


###################
# Testing Section #
###################

if ($TEST) {

	# origin
	print "origin: ";
	print_unit($origin, 0, 0);
	
	my $i0 = $IMAGE[$RES_0]->copy();
	my ($x0, $y0, $a0) = @$origin;
	$i0->circle(color => 'green', 'x'=>$x0, 'y'=>$y0, 'r'=>3);
	my $points = points_on_line([$x0, $y0, $a0, $l0]);
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		$i0->setpixel('x'=>$x, 'y'=>$y, color=>'red');
	}		
	$i0->write(file=>"origin.png") or die Imager->errstr;
		
	# primary vein
	for (my $i = 0; $i < @primary; $i++) {
		my $img = $IMAGE[$RES_0]->copy();
		plot_unit($img, $primary[$i]);
		my $n = '0' x (3 - length($i));
		my $name = "primary-$n$i.png";
		$img->write(file=>"$name") or die Imager->errstr;
	}
	
	my $i1 = $IMAGE[$RES_0]->copy();
	
	foreach my $unit (@primary) {
		my ($x, $y) = @$unit;
		$i1->setpixel('x'=>$x, 'y'=>$y, color=>'red');
		#plot_unit($i1, $unit);
	}
	
	#my $last = $primary[-1];
	#$i1->setpixel('x'=>$last->[0], 'y'=>$last->[1], color=>'yellow');
	#plot_unit($i1, $last);
	
	$i1->write(file=>"primary.png") or die Imager->errstr;
	
	exit;
}

#############################################################################
# Functions
#############################################################################

sub plot_unit {
	my ($img, $unit) = @_;
	my $points = points_on_line($unit);
		
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
	#	print "$x,$y\n";
		$img->setpixel('x'=>$x, 'y'=>$y, color=>'green');
	}
}

sub angle {
	my ($x0, $y0, $x1, $y1) = @_;
	my $dx = $x1 - $x0;
	my $dy = $y1 - $y0;
	my $angle = atan2($dy, $dx);
	return 360 * $angle / (2 * 3.1415); # -180 to 180
}

sub end_point {
	my ($unit) = @_;
	my ($x0, $y0, $a0, $len) = @$unit;
	my $rad = 2 * 3.14159 * $a0 / 360;
	my $x1 = $x0 + cos($rad) * $len;
	my $y1 = $y0 + sin($rad) * $len;
	return [$x1, $y1];
}

sub threshold {
	return 200;


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

sub print_unit {
	my ($unit, $s, $t) = @_;
#	printf "%d,%d %d° %d %d %d\n", @$unit, $s, $t;
	print "@$unit $s $t\n";
}

sub next_unit {
	my ($img, $ori, $arc, $length, $step) = @_;

	my ($x0, $y0, $a0) = @$ori;
	my $aMin = $a0 - $arc;
	my $aMax = $a0 + $arc;
	
	# find best line from here
	my $min_score = 1e30;
	my $best_unit;
	for (my $angle = $aMin; $angle <= $aMax; $angle += $step) {
		my $unit = [$x0, $y0, $angle, $length];
		my $points = points_on_line($unit);
		my $score = score_ave_points($img, $points);
		if ($score < $min_score) {
			$min_score = $score;
			my $new_start = bestest_point($ori, $points);
			$best_unit = [@$new_start, $angle , $length];			
		}
	}
		
	return $best_unit, $min_score;
}

sub bestest_point {
	my ($u1, $units) = @_;
	my ($x0, $y0, $a0) = @$u1;

	foreach my $unit (@$units) {
		my ($x1, $y1) = @$unit;
		next if $x1 == $x0 and $y1 == $y0;
		next if abs($x0 - $x1) > 1 or abs($y0 - $y1) > 1;
		return [$x1, $y1];
	}
		
	die "unexpected";
}

sub find_origin {
	my ($img, $step, $length, $gutter) = @_;
	
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
	# pointing towards the middle
	my ($cx, $cy) = ($xlimit/2, $ylimit/2); # center of image
	my $origin;
	my $min_score = 1e30;
	foreach my $item (@blob) {
		my ($x, $y) = @{$item->{point}};
		my $ta = angle($x, $y, $cx, $cy);
		my $ca = $ta + 180;
		my $a1 = $ta - 45;
		my $a2 = $ta + 45;
		
		for (my $angle = $a1; $angle < $a2; $angle += $step) {
			
			# black vein
			my $u1 = [$x, $y, $angle, $length];
			my $p1 = points_on_line($u1);
			my $s1 = score_ave_points($img, $p1);
			
			# white non-vein, shorter
			my $u2 = [$x, $y, $angle + 180, $length/4];	
			my $p2 = points_on_line($u2);
			my $s2 = score_ave_points($img, $p2);
			
			my $score = $s1 - $s2;
			if ($score < $min_score) {
				$origin = [$x, $y, $angle, $length];
				$min_score = $score;
			}
		}
	}
		
	return $origin;
}

sub score_ave_points {
	my ($img, $points) = @_;
	
	my $sum = 0;
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
		$sum += $val
	}
	
	return int $sum / @$points;
}

sub score_sum_points {
	my ($img, $points) = @_;
	
	my $sum = 0;
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
		$sum += $val
	}
	
	return $sum;
}

sub count_points {
	my ($img, $points, $t) = @_;
		
	my $count = 0;
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
		$count++ if $val >= $t;
	}
	
	return $count;
}

sub points_on_line {
	my ($unit) = @_;
	
	my ($x0, $y0, $a0, $len) = @$unit;
	my $end = end_point($unit);
	my ($x1, $y1) = @$end;
	
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
	
	# return as array of (x,y) pairs
	my @point;
	foreach my $point (keys %point) {
		my ($x, $y) = split(",", $point);
		push @point, [$x, $y];
	}
		
	return \@point;
}


########################
# Single-use Functions #
########################

sub _score_blob {
	my ($img, $x, $y) = @_;
		
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
	
	my @point;
	foreach my $point (@blob) {
		my $ix = $x + $point->[0];
		my $iy = $y + $point->[1];
		push @point, [$ix, $iy];
	}
	
	return score_sum_points($img, \@point);
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

A $unit is a 4-part structure that contains x, y, angle, and length. The
x,y point is considered the MIDDLE of the unit with a head and tail
extending in opposite directions. The angle is the direction of the
HEAD. A @unit is considered an unorderd collection and $units is the
preferred name for a reference of @unit.

A $surface' is a collection of $unit stored in a 2-dimensional hash
reference in which the x and y coordinates are the hash keys. This
prevents unit collision on the surface.

A $graph is an array of $surface whose indices correspond to different
image resolutions.

An $image is an array of Imager objects indexed identically to a
$graph. The highest resolution image is at index 0.

