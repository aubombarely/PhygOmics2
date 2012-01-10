
package PhyGeAnnot;

use strict;
use warnings;
use autodie;

use Carp qw| croak cluck |;
use Math::BigFloat;
use R::YapRI::Base qw/ r_var /;
use R::YapRI::Data::Matrix;
use R::YapRI::Graph::Simple;

use File::Temp qw/ tempfile tempdir/;
use String::Random qw/ random_regex random_string/;
use Cwd;

use FindBin;
use lib "$FindBin::Bin/../lib";

use PhyGeStats;
our @ISA = qw(PhyGeStats);    # inherits from PhyGeStats

###############
### PERLDOC ###
###############

=head1 NAME

PhyGeAnnot.pm
A class with functions to link annotations to objects from
PhyGomics modules

=cut

our $VERSION = '0.01';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

  use PhyGeAnnot;

  my $phygeannot = PhyGeAnnot->new({ topotypes => $hashref });
  $phygeannot->load_blast_annot( $blastfile, 
                                 { defline =>$defline_file, blastdb => 'swp' } 
                               );
  $phygeannot->load_go_annot($gofile);

  $phygeannot->generate_annot();
  my %topo_annot = $phygeannot->get_annot();


=head1 DESCRIPTION

 PhyGeAnnot is a module to assign annotations to the clusters based in 
 anntotations of its members.



=head1 AUTHOR

Aureliano Bombarely <ab782@cornell.edu>


=head1 CLASS METHODS

The following class methods are implemented:

=cut 



############################
### GENERAL CONSTRUCTORS ###
############################

=head2 constructor new

  Usage: my $phygeannot = PhyGeAnnot->new($arguments_href);

  Desc: Create a phygeannot. object with the specified parameters.

  Ret: a PhyGeAnnot.pm object

  Args: A hash reference with the following key-value pairs: 
         + phygetopo  => a hash ref. of phygetopo objects
         + rbase      => a R::YapRI::Base object 
         + gene_annot => a hash ref. with 
                              keys = member_ids, 
                              value = hashref with key = database.
                                                   value = hashref. blast
         + go_annot   => a hash ref. with:
                              keys = member_ids,
                              value = array ref with GO terms.
        
  Side_Effects: Die if the argument used is not a hash or there are argument
                incompatibility.

  Example: my $phygeannot = PhyGeAnnot->new();

=cut

sub new {
    my $class = shift;
    my $args_href = shift;

    my $self = bless( {}, $class );                         
    
    my %permargs = ( 
	rbase        => 'R::YapRI::Base',
	phygetopo    => 'HASH',
	gene_annot   => 'HASH',
	go_annot     => 'HASH',
	);

    ## Check argument

    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ARGUMENT ERROR: $args_href used for new() is not HASH REF.");
	}
	else {
	    my %args = %{$args_href};
	    foreach my $argkey (keys %args) {
		my $exp = $permargs{$argkey};
		unless (defined $exp) {
		    croak("ARG. ERROR: $argkey isnt a permited arg. for new()");
		}
		else {
		    if (ref($args{$argkey}) ne $exp && $args{$argkey} =~ m/./) {
			croak("ARG. ERROR: $args{$argkey} isnt $exp for new()");
		    }
		}	
	    }
	}
    }

    ## As default values ir will create an empty object

    my $phyget_href = $args_href->{phygetopo} || {};
    my $gene_annot_href = $args_href->{gene_annot} || {};
    my $go_annot_href = $args_href->{go_annot} || {};
    my $rbase = $args_href->{phygetopo} || R::YapRI::Base->new();
        
    ## Set vars in the object

    $self->set_phygetopo($phyget_href);
    $self->set_gene_annot($gene_annot_href);
    $self->set_go_annot($go_annot_href);
    
    return $self;
}


#################
### ACCESSORS ###
#################

=head2 get_gene_annot

  Usage: my $gene_annot_href = $phygeannot->get_gene_annot(); 

  Desc: Get gene annotation hash ref. for a phygeannot object

  Ret: An hash reference with key=member_id and value=hashref. with 
       key=database and value hashref. with blast results.

  Args: None

  Side_Effects: None

  Example:  my %gene_annot = %{$phygetopo->get_gene_annot()};

=cut

sub get_gene_annot {
    my $self = shift;
    return $self->{gene_annot};
}

=head2 set_gene_annot

  Usage: $phygeannot->set_gene_annot($gene_annot_href);

  Desc: Set gene annot hash ref. in the phygeannot object

  Ret: None

  Args: An hash reference with key=member_id and value=hashref. with 
        key=database and value hashref. with blast results.

  Side_Effects: Die if no argument is used or if the argument is not a hashref.

  Example: $phygetannot->set_phygetopo(\%phygetopos);

=cut

sub set_gene_annot {
    my $self = shift;
    my $gene_href = shift ||
	croak("ARG. ERROR: No arg. was used for set_gene_annot function");
    
    unless (ref($gene_href) eq 'HASH') {
	croak("ERROR: $gene_href for set_gene_annot() isnt hash ref");
    }
    else {
	foreach my $member (keys %{$gene_href}) {

	    my $annot_href = $gene_href->{$member};
	    unless (ref($annot_href) eq 'HASH') {
		croak("ERROR: href members for set_gene_annot() isnt HASHREF.");
	    }
	    else {
		my %blastdb = %{$annot_href};
		foreach my $bdb (keys %blastdb) {
		    unless (ref($blastdb{$bdb}) eq 'HASH') {
			croak("ERROR: href blastdb set_gene_annot isnt a HREF");
		    }
		}
	    }
	}
	$self->{gene_annot} = $gene_href;    
    }
}

=head2 add_gene_annot

  Usage: $phygeannot->add_gene_annot($member_name, $blastdb, $blasthref);

  Desc: Add a new gene annot. blast result for an specific database

  Ret: None

  Args: $member_name, a member name
        $blastdb, a name for a blastdb
        $blasthref, a hash ref. with key=blast parameter, value=value

  Side_Effects: Die if no argument is used or if the object is not a hash

  Example: $phygeannot->add_gene_annot('Ab457', 'swp', { evalue => '1e-100' });

=cut

sub add_gene_annot {
    my $self = shift;
    my $name = shift ||
	croak("ARG. ERROR: No arg. was used for add_gene_annot function");
    my $blastdb = shift ||
	croak("ARG. ERROR: No blastdb arg. was used for add_gene_annot()");
    my $blasthref = shift ||
	croak("ARG. ERROR: No blast args. were supplied to add_gene_annot()");
    
    unless (ref($blasthref) eq 'HASH') {
	croak("ERROR: $blasthref for add_gene_annot() isnt hashref.");
    }

    if (exists $self->{gene_annot}->{$name}) {
	$self->{gene_annot}->{$name}->{$blastdb} = $blasthref;
    }
    else {
	$self->{gene_annot}->{$name} = { $blastdb => $blasthref };
    }
}


=head2 get_go_annot

  Usage: my $go_annot_href = $phygeannot->get_go_annot(); 

  Desc: Get go annotation hash ref. for a phygeannot object

  Ret: An hash reference with key=member_id and value=hashref. with 
       key=goterm and value=description

  Args: None

  Side_Effects: None

  Example:  my %go_annot = %{$phygetopo->get_go_annot()};

=cut

sub get_go_annot {
    my $self = shift;
    return $self->{go_annot};
}

=head2 set_go_annot

  Usage: $phygeannot->set_go_annot($go_annot_href);

  Desc: Set go annot hash ref. in the phygeannot object

  Ret: None

  Args: An hash reference with key=member_id and value=hashref. with 
        key=goterm, value=description

  Side_Effects: Die if no argument is used or if the argument is not a hashref.

  Example: $phygetannot->set_go_annot({ 'ab342' => { 'GO:0005623' => 'cell' }});

=cut

sub set_go_annot {
    my $self = shift;
    my $memb_go_href = shift ||
	croak("ARG. ERROR: No arg. was used for set_go_annot function");
    
    unless (ref($memb_go_href) eq 'HASH') {
	croak("ERROR: $memb_go_href for set_go_annot() isnt hash ref");
    }
    else {
	foreach my $member (keys %{$memb_go_href}) {

	    my $gohref = $memb_go_href->{$member};
	    unless (ref($gohref) eq 'HASH') {
		croak("ERROR: $gohref for set_go_annot() isnt HASHREF.");
	    }
	}
	$self->{go_annot} = $memb_go_href;    
    }
}

=head2 add_go_annot

  Usage: $phygeannot->add_go_annot($member_name, $gohref);

  Desc: Add a new go annot. blast result for an specific database

  Ret: None

  Args: $member_name, a member name
        $gohref, a hash ref. with key=go_id, value=description

  Side_Effects: Die if no argument is used or if the object is not a hash

  Example: $phygeannot->add_go_annot('Ab457', { 'GO:0005623' => 'cell' });

=cut

sub add_go_annot {
    my $self = shift;
    my $name = shift ||
	croak("ARG. ERROR: No arg. was used for add_go_annot function");
    my $gohref = shift ||
	croak("ARG. ERROR: No go href args. were supplied to add_go_annot()");
    
    unless (ref($gohref) eq 'HASH') {
	croak("ERROR: $gohref for add_go_annot() isnt hashref.");
    }

    $self->{go_annot}->{$name} = $gohref;    
}

#######################
## PARSING FUNCTIONS ##
#######################

=head2 parse_go_file

  Usage: my $go_href = parse_go_file($filename, $args_href);

  Desc: Parse a go annotation file and return a hash with key=member and
        value=hash ref of GO terms.
        It can parse the GO terms file in two ways:
        1) <ID><tab><GOTERM1><semicolon><GOTERM2>...
        2) <ID><tab><GOTERM1><=><description1><;><GOTERM2><=><description2>

  Ret: $go_href, a hash ref.

  Args: $filename, filename with goterms to parse
        $args_href, hash ref. with args. For now valid keys are:
        report_status

  Side_Effects: Die if no argument is supplied.

  Example: my $go_href = parse_go_file($filename, { report_status => 1 });

=cut

sub parse_go_file {
    my $filename = shift ||
	croak("ARG. ERROR: No arg. was used for parse_go_file function");
    my $arghref = shift;
    
    if (defined $arghref && ref($arghref) ne 'HASH') {
	croak("ERROR: $arghref for parse_go_file() isnt hashref.");
    }

    my %go = ();
    
    ## To report status

    my $L = `cut -f1 $filename | wc -l`;
    chomp($L);
    my $l = 0;

    my $rep_st = $arghref->{report_status} || 0;

    open my $gofh, '<', $filename;
    while (<$gofh>) {
	$l++;
	chomp($_);
    
	my @data = split(/\t/, $_);
	if (defined $data[0]) {
	    $go{$data[0]} = {};
	    if (defined $data[1]) {
		my @go = split(/;/, $data[1]);
		foreach my $go (@go) {
		    $go =~ s/^\s+//;
		    $go =~ s/\s+$//;
		    if ($go =~ m/(GO:\d+)=(.+)/) {
			$go{$data[0]}->{$1} = $2;
		    }
		    else {
			$go{$data[0]}->{$go} = '';
		    }
		}
	    }
	}
	
	if ($rep_st =~ m/^(1|Y)/i ) {
	    PhyGeCluster::print_parsing_status($l, $L, 
					       "Percentage of go file parsed:");
	}
    }

    return \%go;    
}


=head2 load_go_file

  Usage: $phygeannot->load_go_file($filename, $args_href);

  Desc: Load a parsed go file into the phygeannot. object.

  Ret: None

  Args: $filename, filename with goterms to parse
        $args_href, hash ref. with args. For now valid keys are:
        report_status

  Side_Effects: Die if no argument is supplied.

  Example: $phygeannot->load_go_file($filename, $args_href);

=cut

sub load_go_file {
    my $self = shift;
    my $filename = shift ||
	croak("ARG. ERROR: No arg. was used for load_go_file function");
    my $arghref = shift;
    
    if (defined $arghref && ref($arghref) ne 'HASH') {
	croak("ERROR: $arghref for load_go_file() isnt hashref.");
    }

    my %go = %{parse_go_file($filename, $arghref)};

    foreach my $member (sort keys %go) {
	$self->add_go_annot($member, $go{$member});
    }
}

=head2 parse_blast_file

  Usage: my $blast_href = parse_blast_file($blastresult, $args_href);

  Desc: Parse blast file result.

  Ret: $blast_href, a hash reference with: key=member_id and value=hashref. 
       with key=database and value hashref. with blast results.

  Args: $filename, filename with goterms to parse
        $args_href, hash ref. with args. For now valid keys are:
         blastdb       => name of the database used for the blast.
         defline       => defline file with <ID><tab><description>
         report_status => 1

  Side_Effects: Die if no argument is supplied.
                It always will get the best match.
                Use fastacmd over the db to retrieve the description for
                the better match.

  Example: my $blast_href = parse_blast_file( $filename, 
                                              { report_status => 1,
                                                blastdb       => 'swissprot',
                                                defline       => $file
					      });

=cut

sub parse_blast_file {
    my $filename = shift ||
	croak("ARG. ERROR: No arg. was used for parse_blast_file function");
    my $arghref = shift;
 
    unless (defined -s $filename) {
	croak("ARG. ERROR: Blast result file doesnt exists or has zero size.");
    }

    if (defined $arghref && ref($arghref) ne 'HASH') {
	croak("ERROR: $arghref for parse_blast_file() isnt hashref.");
    }

    ## Check that exists defline and blastdb

    my $blastdb = $arghref->{blastdb} ||
	croak("ARG. ERROR: No blastdb arg. was supplied to parse_blast_file");

    my $defline = $arghref->{defline} ||
	croak("ARG. ERROR: No defline arg. was supplied to parse_blast_file");

    unless (defined -s $defline) {
	croak("ARG. ERROR: Defline file doesnt exists or has zero size.");
    }

    my %blast = ();
    
    ## To report status

    my $L = `cut -f1 $filename | wc -l`;
    chomp($L);
    my $l = 0;

    my $rep_st = $arghref->{report_status} || 0;


    ## Open the file and get the descriptions

    open my $blfh, '<', $filename;
    while (<$blfh>) {
	$l++;
	chomp($_);
    
	my @fields = ('query_id', 'subject_id', 'percentage_identity',
		      'alignment_length', 'mismatches', 'gap_openings',
		      'q.start', 'q.end', 's.start', 's.end', 'e-value', 
		      'bit_score');

	my @data = split(/\t/, $_);

	my $i = 0;
	unless (exists $blast{$data[0]}) {
	    my %data = ();
	    foreach my $data (@data) {
		$data{$fields[$i]} = $data;
		$i++;
	    }
	    $blast{$data[0]} = { $blastdb => \%data };

	    ## Get the description from defline

	    my $syscmd = "grep '$data[1]' $defline";
	    my $descr = `$syscmd`;

	    if (defined $descr) {
		
		chomp($descr);
		$descr =~ s/^>//;
		if( $descr =~ m/^.+$data[1]\s(.+)$/) {
		    my @descrs = split(/>/, $1);
		    $blast{$data[0]}->{$blastdb}->{description} = $descrs[0];
		}
		else {
		    $blast{$data[0]}->{$blastdb}->{description} = '';
		}
	    }
	    else {
		$blast{$data[0]}->{$blastdb}->{description} = '';
	    }
	}

	if ($rep_st =~ m/^(1|Y)/i ) {
	    PhyGeCluster::print_parsing_status($l, $L, 
					       "Percentage of go file parsed:");
	}
    }


    return \%blast;    
}

=head2 load_blast_file

  Usage: $phygeannot->load_blast_file($filename, $args_href);

  Desc: Load a parsed blast file into the phygeannot. object.

  Ret: None

  Args: $filename, filename with goterms to parse
        $args_href, hash ref. with args. For now valid keys are:
         blastdb       => name of the database used for the blast.
         defline       => defline file with <ID><tab><description>
         report_status => 1

  Side_Effects: Die if no argument is supplied or they are wrong.

  Example: $phygeannot->load_blast_file($filename, $args_href);

=cut

sub load_blast_file {
    my $self = shift;
    my $filename = shift ||
	croak("ARG. ERROR: No arg. was used for load_blast_file function");
    my $arghref = shift;
    
    if (defined $arghref && ref($arghref) ne 'HASH') {
	croak("ERROR: $arghref for load_blast_file() isnt hashref.");
    }

    my %blast = %{parse_blast_file($filename, $arghref)};

    foreach my $member (sort keys %blast) {
	my %bldbs = %{$blast{$member}};
	foreach my $db (keys %bldbs) {
	    $self->add_gene_annot($member, $db, $bldbs{$db});
	}
    }
}




##########################
## ANALYTICAL FUNCTIONS ##
##########################

=head2 go_conservative_annotation

  Usage: $phygeannot->go_conservative_annotation();

  Desc: Run conservative annotation over members of the phygetopo object.
        Get the annotation for each of the members of the cluster of each
        topology and add to the cluster removing the redundance.
        It will store the annotation as 'annotation' for each PhyGeTopo object.

  Ret: None

  Args: None

  Side_Effects: Die if go terms are not set

  Example: $phygeannot->go_conservative_annotation();

=cut

sub go_conservative_annotation {
    my $self = shift;

    my %phygetopo = %{$self->get_phygetopo()};
    if (scalar(keys %phygetopo) == 0) {
	croak("No phygetopo was set. Aborting go_conservative_annotation");
    }

    my %go = %{$self->get_go_annot()};
    if (scalar(keys %go) == 0) {
	croak("No GO was set. Aborting go_conservative_annotation");
    }

    foreach my $method (keys %phygetopo) {
	my $phygetopo = $phygetopo{$method};

	
	my $annotation_href = $phygetopo->get_annotations();
	my %seqfams = %{$phygetopo->get_seqfams()};
	
	foreach my $id (keys %seqfams) {
	    
	    my %go_seqfam = ();
	    my @members = $seqfams{$id}->get_members();
	    foreach my $member (@members) {
		my $memb_id = $member->id();
		
		if (exists $go{$memb_id}) {
		    my %go_memb = %{$go{$memb_id}};
		    foreach my $go (keys %go_memb) {
			unless (exists $go_seqfam{$go}) {
			    $go_seqfam{$go} = $go_memb{$go};
			}
		    }
		}
	    }

	    if (exists $annotation_href->{$id}) {
		$annotation_href->{$id}->{'GO'} = \%go_seqfam;
	    }
	    else {
		$annotation_href->{$id} = {'GO' => \%go_seqfam };
	    }
	}
    }
}




####
1; #
####
