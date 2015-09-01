#!/bin/env perl
use strict;
use warnings 'FATAL' => 'all';
use Imager;
use DataBrowser;
use Getopt::Std;
use vars qw($opt_t);
getopts('t');

## GLOBALS ##

my $SCALE = 3;
my $MAXRES = 1;

## Command Line ##

die "
usage: veintrace.pl [options] <image_file>
  -s <int>    scale [$SCALE]
  -t          test mode
" unless @ARGV == 1;
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
my $s0 = 10; # degrees per step for origin
my $h0 = 8; # head length
my $t0 =  4; # tail length
my $g0 = 11; # image gutter
my $origin = find_origin($img[0], $s0, $h0, $t0, $g0);

## Trace Main Vein ##
my $a1 = 20; # arc degrees
my $s1 = 5;  # degrees per step
my $h1 = 5; # head length
my $t1 = 5; # tail length

my @primary;
my $unit = $origin;
my $count = 0;
my %seen;
print STDERR "tracing primary vein";
my $primary_score = 0;
while (1) {
	print STDERR ".";
	my $t = threshold($img[0], $unit, $a1, $s1);
	my ($next, $score) = next_unit($img[0], $unit, $a1, $h1, $t1, $s1);
	
		
	if ($score < $t) {
		my $s = "$next->[0],$next->[1]";
		$primary_score += $score;
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
print STDERR "\n";

###################
# Testing Section #
###################

if ($opt_t) {

	# origin
	my $i0 = $img[0]->copy();
	plot_unit($i0, $origin);		
	$i0->write(file=>"origin.png") or die Imager->errstr;	
		
	# primary vein	
	my $i1 = $img[0]->copy();
	foreach my $unit (@primary) {
		my ($x, $y) = @$unit;
		$i1->setpixel('x'=>$x, 'y'=>$y, color=>'red');
	}
	$i1->write(file=>"primary.png") or die Imager->errstr;
	
	exit;
	
	
	# all paths on the primary vein	
	for (my $i = 0; $i < @primary; $i++) {
		my $img = $img[0]->copy();
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
	
	my @point; # non-redundant points on the line
	
	my $score = 0;
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

sub distance {
	my ($x0, $y0, $x1, $y1) = @_;
	return sqrt(($x0-$x1)**2 + ($y0-$y1)**2);
}

sub next_unit {
	my ($img, $ori, $arc, $hlen, $tlen, $step) = @_;

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
	my $min_score = 1e30;
	my $opt_unit;
	foreach my $start (@start) {
		my ($nx0, $ny0, $nx1, $ny1, $na0);
		for (my $angle = $aMin; $angle <= $aMax; $angle += $step) {
			my $unit = [@$start, $angle, $hlen, $tlen];
			my $score = score_unit($img, $unit);
			if ($score < $min_score) {
				$min_score = $score;
				$opt_unit = $unit;
			}
		}
	}
		
	return $opt_unit, $min_score;
}

sub next_unit_old {
	my ($img, $ori, $arc, $hlen, $tlen, $step) = @_;

	my ($x0, $y0, $a0) = @$ori;
	my $aMin = $a0 - $arc;
	my $aMax = $a0 + $arc;
	
	# find optimal (x, y, angle) from here
	my $min_score = 1e30;
	my ($nx0, $ny0, $nx1, $ny1, $na0);
	for (my $angle = $aMin; $angle <= $aMax; $angle += $step) {
		my $unit = [$x0, $y0, $angle, $hlen, $tlen];
		my $score = score_unit($img, $unit);
		if ($score < $min_score) {
			$min_score = $score;
			my $points = points_in_head($unit);
			my $first = shift @$points;
			my $last = pop @$points;
			($nx0, $ny0) = @$first;
			($nx1, $ny1) = @$last;
			$na0 = angle($nx0, $ny0, $nx1, $ny1);
		}
	}
	my $next_unit = [$nx0, $ny0, $na0, $hlen, $tlen];
	
	return $next_unit, $min_score;
}

sub threshold {
	return 150; # temporary


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
			
	# identify origin as unit & following white-space
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
			my $tail = tail($unit);
			my ($tx, $ty) = @$tail;
			my $anti = [$tx, $ty, $angle+180, $tlen, 0];
			my $uscore = score_unit($img, $unit);
			my $ascore = score_unit($img, $anti);
			my $score = $uscore - $ascore;
			
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
	foreach my $point (@$points) {
		my ($x, $y) = @$point;
		my ($val) = $img->getpixel('x' => $x, 'y' => $y)->rgba;
		$sum += $val;
	}
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
	$img->setpixel('x'=>$unit->[0], 'y'=>$unit->[1], color=>'yellow');
}

sub print_unit {
	my ($unit, $score) = @_;
	$score = 0 if not defined $score;
	printf "%d,%d %d° %d %d %d\n", @$unit, $score;
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

