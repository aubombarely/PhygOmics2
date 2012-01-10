
package PhyGeCluster;

use strict;
use warnings;
use autodie;

use Carp qw| croak cluck |;
use Try::Tiny;
use Math::BigFloat;

use FindBin;
use lib "$FindBin::Bin/../lib";

## Phygomics modules ########################
use PhyGeBoots;
use Strain::Composition;
use Bio::Align::Overlaps;
use Bio::Tools::Run::Phylo::Phylip::Dnaml;
#############################################

## Bioperl modules ##########################
use Bio::Seq::Meta;
use Bio::LocatableSeq;
use Bio::SeqIO;
use Bio::SearchIO;
use Bio::Cluster::SequenceFamily;

use Bio::Tools::Run::Alignment::Clustalw;
use Bio::Tools::Run::Alignment::Kalign;
use Bio::Tools::Run::Alignment::MAFFT;
use Bio::Tools::Run::Alignment::Muscle;
use Bio::Tools::Run::Alignment::TCoffee;
use Bio::Tools::Run::StandAloneBlast;

use Bio::AlignIO;
use Bio::Align::DNAStatistics;
use Bio::Align::PairwiseStatistics;

use Bio::Tools::Run::Phylo::Phylip::SeqBoot;

use Bio::Matrix::IO;
use Bio::Matrix::Generic;
use Bio::TreeIO;
#############################################


###############
### PERLDOC ###
###############

=head1 NAME

PhyGeCluster.pm
A class to cluster sequences and analyze clusters.

=cut

our $VERSION = '0.01';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

  use PhyGeCluster;

  ## To get each cluster from a blast file

  my $phygecluster = PhyGeCluster->new({
                                   acefile       => $filename1a,
                                   blastfile     => $filename1b,
                                   blastformat   => $format, 
                                   sequencefile  => $filename2,
                                   strainfile    => $filename3,   
                                   clustervalues => { $variable => $condition},
                                   rootname      => $name,
                                   });

  ## Accessors

  $phygecluster->set_clusters(\%clusters);
  my $clusters_href = $phygecluster->get_clusters();

  $phygecluster->set_strains(\%strains);
  my $strains_href = $phygecluster->get_strains();

  $phygecluster->set_distances(\%distances);
  my $distances_href = $phygecluster->get_distances();

  $phygecluster->set_bootstrapping(\%bootstrap);
  my $bootstrap_href = $phygecluster->get_bootstrapping();

  ## Load new sequences into the object

  $phygecluster->load_seqfile($seqfile);

  ## Load new strains

  $phygecluster->load_strainfile($strainfile); 

  ## Calculate the alignment

  $phygecluster->run_alignments();

  ## Calculate distances

  $phygecluster->run_distances();

  ## Create bootstraing of the alignments

  $phygecluster->run_bootstrapping({ datatype => 'Sequences', quiet => 'yes' });

  ## Select by cluster sizes

  my %cluster_sizes = phygecluster->cluster_sizes();
  my %singlets = phygecluster->cluster_sizes(1,1);

  ## Prune by alignments features

  $phygecluster->prune_by_align({num_sequences => ['<',4],length => ['<',100]});

  ## Prune by strains composition

  $phygecluster->prune_by_strains({ composition => {'A' => 1,'B' => 1,'C' => 1},
                                    min_distance => [['A','B'],['A','C']] });


  ## Prune and slice by overlapping region

  $phygecluster->prune_by_overlappings(
                 { composition => {'A' => 1,'B' => 1,'C'=> 2},
                   trim        => 1,
  );

=head1 DESCRIPTION

 Object to parse and cluster sequences based in blast results


=head1 AUTHOR

Aureliano Bombarely <ab782@cornell.edu>


=head1 CLASS METHODS

The following class methods are implemented:

=cut 



############################
### GENERAL CONSTRUCTORS ###
############################

=head2 constructor new

  Usage: my $phygecluster = PhyGeCluster->new($arguments_href);

  Desc: Create a phygecluster object
        Use fastblast_parser argument to use the non-bioperl
        blast parser (faster)

  Ret: a PhyGeCluster.pm object

  Args: A hash reference with the following keys: 
         + acefile, $filename, a scalar for file in ace format
         + blastfile, $filename a scalar for a blast result file.
         + blastformat, $fileformat, a scalar
         + fastblast_parser, 1, a scalar
         + clustervalues, a hash reference argument (see parse_blastfile())
         + rootname, $name a scalar. 
         + sequencefile, $filename, a scalar 
         + strainfile, $filename, a scalar
         + run_alignments, a hash reference argument (see run_alignments())  
         + run_distances, a hash reference argument (see run_distances())
         + run_bootstrapping, a hash reference arg. (see run_bootstrapping())
         + reportstatus, a switch to enable/disable report status option.

  Side_Effects: Die if the argument used is not a hash or there are argument
                incompatibility (such as use fastblast_parser without blastfile)
                
                Default values when blastfile argument is used:
                { blastformat   => 'blasttable'.
                  clustervalues => { "percent_identity" => ['>', 90], 
                                     "hsp_length"       => ['>', 60], },
                  rootname      => 'cluster',
                }

  Example: my $phygecluster = PhyGeCluster->new(%arguments);

=cut

sub new {
    my $class = shift;
    my $args_href = shift;

    my $self = bless( {}, $class );                         
    
    my %clusters = ();
    my %strains = ();
    my %dist = ();
    my %bootstrap = ();

    ## Check argument compatibility

    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ARGUMENT ERROR: $args_href used for new() is not HASH REF.");
	}
    }

    ## Enable/Disable report status

    my $repstatus = $args_href->{reportstatus};
    if (defined $repstatus && $repstatus =~ m/^(1|yes)$/i) {
	$self->enable_reportstatus();
    }
    else {
	$self->disable_reportstatus();
    }

    ## Check parser compatibility and run them

    my $err = "ARGUMENT INCOMPATIBILITY for new() function: ";
    unless(defined $args_href->{'blastfile'}) {

	if (defined $args_href->{'fastblast_parser'}) {
	    $err .= "fastblast_parser arg. can not be used without blastfile.";
	    croak($err);	    
	}
	unless(defined $args_href->{'acefile'}) {
	    if (defined $args_href->{'strainfile'}) {
		$err .= "strainfile arg. can not be used without blastfile";
		$err .= " or acefile argument.";
		croak($err);	    
	    }
	}
	if (defined $args_href->{'sequencefile'}) {
	    $err .= "sequencefile arg. can not be used without blastfile arg.";
	    croak($err);	    
	}
    }
    else {
	if (defined $args_href->{'acefile'}) {
	    $err .= "acefile arg. can not be used with blastfile arg.";
	    croak($err);
	}
	unless (defined $args_href->{'sequencefile'})  {
	    if (defined $args_href->{'run_alignments'}) {
		$err .= "run_alignments arg. can not be used without ";
		$err .= "sequencefile arg.";
		croak($err);
	    }
	}
	else {
	    unless (defined $args_href->{'run_alignments'})  {
		if (defined $args_href->{'run_distances'}) {
		    $err .= "run_distances arg. can not be used without ";
		    $err .= "run_alignments arg.";
		    croak($err);
		}
		if (defined $args_href->{'run_bootstrapping'}) {
		    $err .= "run_bootstrapping arg. can not be used without ";
		    $err .= "run_alignments arg.";
		    croak($err);
		}
	    }
	}
    }

    if (defined $args_href->{'blastfile'}) {

	## Get the cluster information from blast file
	
	if (defined $args_href->{'fastblast_parser'}) {
	    %clusters = fastparse_blastfile($args_href);
	}
	else {
	    %clusters = parse_blastfile($args_href);
	}
    }	

    if (defined $args_href->{'acefile'}) {
	
	%clusters = parse_acefile($args_href);	
    }	

    $self->set_clusters(\%clusters);

    ## Parse the seqfile if exists

    if (defined $args_href->{'sequencefile'}) {
	$self->load_seqfile($args_href);	
    }

    ## Parse the strain file if exists

    if (defined $args_href->{'strainfile'}) {
	%strains = parse_strainfile($args_href);
    }

    $self->set_strains(\%strains);

    ## This will use the run_alignment and run_distance function
    ## only if the sequencefile argument was detailed (it was checked in the
    ## begining of the function). Also it will run bootstrapping if it is
    ## defined the argument

    if (defined $args_href->{'run_alignments'}) {
	    
	$self->run_alignments($args_href->{'run_alignments'});
		
	if (defined $args_href->{'run_distances'}) {

	    %dist = $self->run_distances($args_href->{'run_distances'});
	}

	my $bootsargs = $args_href->{'run_bootstrapping'};

	if (defined $bootsargs) {
	    
	    %bootstrap = $self->run_bootstrapping($bootsargs);
	}
    }

    $self->set_distances(\%dist);
    $self->set_bootstrapping(\%bootstrap);


    return $self;
}

=head2 constructor clone

  Usage: my $new_phygecluster = $old_phygecluster->clone();

  Desc: Create a new phygecluster object using a old one

  Ret: a PhyGeCluster.pm object

  Args: None

  Side_Effects: None

  Example: my $new_phygecluster = $old_phygecluster->clone();

=cut

sub clone {
    my $self = shift;

    ## Create an empty object:

    my $new_phygecluster = __PACKAGE__->new();

    ## Switch report status for this object if it is enabled

    if ($self->is_on_reportstatus) {
	$new_phygecluster->enable_reportstatus();
    }

    ## Get the data from the old object

    my %clusters = %{$self->get_clusters()};
    my %strains = %{$self->get_strains()};
    my %distances = %{$self->get_distances()};
    my %bootstrap = %{$self->get_bootstrapping()};
    
    ## Clone also the Bio::Cluster::SequenceFamily, Bio::SimpleAlign.
    ## It will have the same Bio::Seq objects

    my $total_cluster = scalar(keys %clusters);
    my $n_cluster = 0;

    my %new_clusters = ();
    foreach my $cluster_id (sort keys %clusters) {
	my $old_seqfam = $clusters{$cluster_id};
	my @members = $old_seqfam->get_members();
	my $old_align = $old_seqfam->alignment();
	my $old_tree = $old_seqfam->tree();

	$n_cluster++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($n_cluster, $total_cluster, 
				 "\t\tPercentage of clusters cloned",
				 $cluster_id,
		);
	}

	my $new_align = '';
	if (defined $old_align) {
	   
	    $new_align = $old_align->select(1, $old_align->num_sequences());

	    ## Select does not copy metadata, so it will transfer manually
	    my @transfers = ('description', 'score', 'source');

	    foreach my $transf_var (@transfers) {
		if (defined $old_align->$transf_var) {
		    $new_align->$transf_var($old_align->$transf_var());
		}
	    }
	}

	my $new_tree = '';
	if (defined $old_tree) {
	    $new_tree = $old_tree->clone();	
	}

	my $new_seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $cluster_id,
	    -members   => \@members,
	    );
	$new_seqfam->alignment($new_align);
	$new_seqfam->tree($new_tree);
	$new_clusters{$cluster_id} = $new_seqfam;
    }
    
    ## %strains has not internal object so it will clone this hash
    ## %distance matrix will not be modify (usually it could rerun the
    ## distances using run_distances)

    ## Set the old dat into the new object

    $new_phygecluster->set_clusters(\%new_clusters);
    $new_phygecluster->set_strains(\%strains);
    $new_phygecluster->set_distances(\%distances);
    $new_phygecluster->set_bootstrapping(\%bootstrap);

    return $new_phygecluster;
}

################
### SWITCHES ###
################

=head2 enable/disable_reportstatus

  Usage: $phygecluster->enable_reportstatus();
         $phygecluster->disable_reportstatus();

  Desc: Enable/disable the switch report status

  Ret: none
 
  Args: None
 
  Side_Effects: None
 
  Example: $phygecluster->enable_reportstatus();
           $phygecluster->disable_reportstatus();

=cut 

sub enable_reportstatus {
    my $self = shift;
    $self->{reportstatus} = 1;
}

sub disable_reportstatus {
    my $self = shift;
    $self->{reportstatus} = 0;
}

=head2 is_on_reportstatus

  Usage: my $boolean = $phygecluster->is_on_reportstatus();

  Desc: Get 0 or 1 for reportstatus switch

  Ret: a boolean, 0 or 1.
 
  Args: None
 
  Side_Effects: None
 
  Example: if ($phygecluster->is_on_reportstatus() ) {
               print STDERR "REPORT";
           }

=cut 

sub is_on_reportstatus {
    my $self = shift;
    return $self->{reportstatus};
}



#################
### ACCESSORS ###
#################

=head2 get_clusters

  Usage: my $clusters_href = $phygecluster->get_clusters();

  Desc: Get a cluster data from PhyGeCluster object

  Ret: A hash refence with key=clustername and 
       value=Bio::Cluster::SequenceFamily object
 
  Args: None
 
  Side_Effects: None
 
  Example: my $clusters_href = $phygecluster->get_clusters();

=cut

sub get_clusters {
  my $self = shift;

  return $self->{clusters};
}


=head2 set_clusters

  Usage: $phygecluster->set_clusters(\%clusters);

  Desc: Set a cluster data from PhyGeCluster object

  Ret: None
 
  Args: A hash with key=clustername and value=Bio::Cluster::SequenceFamily
        object
 
  Side_Effects: Die if the argument is not a hash reference
                or if the values for the hash are not 
                Bio::Cluster::SequenceFamily objects
 
  Example: $phygecluster->set_clusters(\%clusters);

=cut

sub set_clusters {
  my $self = shift;
  my $clusters_href = shift;

  if (defined $clusters_href) {
	if (ref($clusters_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $clusters_href is not a hash reference.\n");
	}
	else {
	    
            ## Check the objects

	    foreach my $cluster_name (keys %{$clusters_href}) {
		my $cluster = $clusters_href->{$cluster_name};
		if (ref($cluster) ne 'Bio::Cluster::SequenceFamily') {
		    croak("ARGUMENT ERROR: value for cluster=$cluster_name IS
                           NOT a Bio::Cluster::SequenceFamily object.\n");
		}
	    }

	    ## If it has survive to the checking it will set the object
	    
	    $self->{clusters} = $clusters_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_clusters function\n");
  }
}


=head2 add_cluster

  Usage: $phygecluster->add_cluster($cluster_name, $member_aref);

  Desc: Add a new cluster to the PhyGeCluster object

  Ret: None
 
  Args: $cluster_name, a scalar
        $member_aref, an array reference with member as Bio::Seq objects
 
  Side_Effects: Die if the arguments are wrong or undef
 
  Example: $phygecluster->add_cluster('cluster_1', ['seq1', 'seq2']);

=cut

sub add_cluster {
  my $self = shift;
  my $cluster_name = shift ||
      croak("ARG. ERROR: No argument was supplied to add_cluster function.\n");
  my $member_aref = shift ||
      croak("ARG. ERROR: None member array ref. was added to add_cluster.\n");

  unless (ref($member_aref) eq 'ARRAY') {
      croak("ARG. ERROR: member array ref. argument is not an ARRAY REF.\n");
  }

  ## Check the members

  foreach my $memberseq (@{$member_aref}) {
      unless (ref($memberseq) =~ m/Bio::Seq/) {
	  croak("ARG. ERROR: member=$memberseq used for add_cluster is not an 
                 Bio::Seq object.\n");
      }
  }

  ## First, create the cluster object

  my $new_cluster = Bio::Cluster::SequenceFamily->new( 
      -family_id => $cluster_name,
      -members   => $member_aref,
      );

  ## Second get the clusters and add a new one
  
  my $clusters_href = $self->get_clusters();
  $clusters_href->{$cluster_name} = $new_cluster;
}


=head2 remove_cluster

  Usage: my $rm_cluster = $phygecluster->remove_cluster($cluster_name);

  Desc: Remove a new cluster to the PhyGeCluster object

  Ret: The value of the cluster removed (a Bio::Cluster::SequenceFamily object)
 
  Args: $cluster_name, a scalar
 
  Side_Effects: Die if the arguments are wrong or undef
 
  Example: my $rm_cluster = $phygecluster->remove_cluster('cluster_1');

=cut

sub remove_cluster {
  my $self = shift;
  my $cluster_name = shift ||
      croak("ARG. ERROR: No argument was supplied to remove_cluster().\n");
  
  my $clusters_href = $self->get_clusters();
  my $value = delete($clusters_href->{$cluster_name});
  return $value;
}

=head2 find_cluster

  Usage: my $cluster = $phygecluster->find_cluster($member_id);

  Desc: Find a cluster object by member_id

  Ret: A Bio::Cluster::SequenceFamily object
 
  Args: $member_id, an scalar
 
  Side_Effects: return undef if the member does not exist
 
  Example: my $cluster = $phygecluster->find_cluster('seq_id1');

=cut

sub find_cluster {
  my $self = shift;
  my $member_id = shift;
  
  my $cluster_found;
  my $clusters_href = $self->get_clusters();
  foreach my $cluster_name (keys %{$clusters_href}) {
      my $cluster = $clusters_href->{$cluster_name};
      
      foreach my $member ($cluster->get_members()){
	  if ($member->display_id eq $member_id) {
	      $cluster_found = $cluster;
	  }
      }
  }

  return $cluster_found;
}

=head2 get_strains

  Usage: my $strains_href = $phygecluster->get_strains();

  Desc: Get a strain data from PhyGeCluster object

  Ret: A hash refence with key=member_id and value=strain
 
  Args: None
 
  Side_Effects: None
 
  Example: my $strains_href = $phygecluster->get_strains();

=cut

sub get_strains {
  my $self = shift;

  return $self->{strains};
}


=head2 set_strains

  Usage: $phygecluster->set_strains(\%strains);

  Desc: Set a strain data from PhyGeCluster object

  Ret: None
 
  Args: A hash with key=member_id and value=strain
 
  Side_Effects: Die if the argument is not a hash refence
 
  Example: $phygecluster->set_strains(\%strains);

=cut

sub set_strains {
  my $self = shift;
  my $strains_href = shift;

  if (defined $strains_href) {
	if (ref($strains_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $strains_href is not a hash reference.\n");
	}
	else {	    
	    $self->{strains} = $strains_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_strains function\n");
  }
}

=head2 get_distances

  Usage: my $distances_href = $phygecluster->get_distances();

  Desc: Get distance data from PhyGeCluster object

  Ret: A hash refence with key=member_id and 
       value=Bio::Matrix::PhylipDist object
 
  Args: None
 
  Side_Effects: None
 
  Example: my $distances_href = $phygecluster->get_distances();

=cut

sub get_distances {
  my $self = shift;

  return $self->{distances};
}


=head2 set_distances

  Usage: $phygecluster->set_distances(\%distances);

  Desc: Set a distance data from PhyGeCluster object

  Ret: None
 
  Args: A hash reference with key=member_id and 
        value=Bio::Matrix::PhylipDist object
 
  Side_Effects: Die if the argument is not a hash reference
 
  Example: $phygecluster->set_distances(\%distances);

=cut

sub set_distances {
  my $self = shift;
  my $distances_href = shift;

  if (defined $distances_href) {
	if (ref($distances_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $distances_href is not a hash reference.\n");
	}
	else {	    
	    $self->{distances} = $distances_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_distances function");
  }
}


=head2 get_bootstrapping

  Usage: my $bootstrapping_href = $phygecluster->get_bootstrapping();

  Desc: Get distance data from Bio::Tree::Tree consensus object

  Ret: A hash reference: 
       my $href = { $cluster_id => Bio::Tree::Tree object }
 
  Args: None
 
  Side_Effects: None
 
  Example: my $bootstrapping_href = $phygecluster->get_bootstrapping();

=cut

sub get_bootstrapping {
  my $self = shift;

  return $self->{bootstrapping};
}


=head2 set_bootstrapping

  Usage: $phygecluster->set_bootstrapping(\%bootstrap);

  Desc: Set bootstrapping data for a PhyGeCluster object.

  Ret: None
 
  Args: A hash reference: 
        my $href = { $cluster_id => Bio::Tree::Tree object }
 
  Side_Effects: Die if the argument is not a hash reference, if the values for
                this hash reference are not array reference and if the members
                of these arrays references are not Bio::SimpleAlign objects
 
  Example: $phygecluster->set_bootstrapping(\%bootstrap);

=cut

sub set_bootstrapping {
  my $self = shift;
  my $bootstrap_href = shift;

  if (defined $bootstrap_href) {
	if (ref($bootstrap_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $bootstrap_href is not a hash reference.\n");
	}
	else {
	    foreach my $cl_id (keys %{$bootstrap_href}) {
		unless (ref($bootstrap_href->{$cl_id}) eq 'Bio::Tree::Tree') {
		    my $err = "VAL. ERROR: value for $cl_id isnt a Bio::Tree";
		    $err .= "object for set_bootstrapping() function.";
		    croak($err);
		}
	    }
	    $self->{bootstrapping} = $bootstrap_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_boostrapping funct.");
  }
}



###################################
## OBJECT DATA LOADING FUNCTIONS ##
###################################

=head2 load_seqfile

  Usage: $phygecluster->load_seqfile($arguments_href);

  Desc: Parse the sequence file using parse_seqfile function and
        load the results into the PhyGeCluster object

  Ret: None

  Args: A hash reference with the following key: sequencefile

  Side_Effects: Die if the argument used is not a hash or if none 
                sequencefile is detailed.
                Ignore the sequences that are not into the 
                Bio::Cluster::SequenceFamily object

  Example: $phygecluster->load_seqfile($arguments_href);

=cut

sub load_seqfile {
    my $self = shift;
    my $args_href = shift;
    
    if (defined $args_href) {
	if (ref($args_href) ne 'HASH') {
	    croak("ARG. ERROR: $args_href is not a hash reference.\n");
	}
	unless (defined $args_href->{'sequencefile'}) {
	    croak("ARG. ERROR: 'sequencefile' is not defined for $args_href\n");
	}
	else {

	    ## First, get the sequences.

	    my %seqs = parse_seqfile->($args_href);

	    ## Get the clusters and the different members

	    my %clusters = %{$self->get_clusters()};
	    foreach my $cluster_id (keys %clusters) {
		my $seqcluster_obj = $clusters{$cluster_id};
		my @members = $seqcluster_obj->get_members();
		
		foreach my $seqmember (@members) {
		    my $seq = $seqs{$seqmember->display_id()};
		    if (defined $seq) {
			$seqmember->seq($seq->seq());
		    }
		}  
	    }
	    
	}
    }
    else {
      	croak("ARG. ERROR: No argument was used for load_seqfile function\n");
    }
}

=head2 load_strainfile

  Usage: $phygecluster->load_strainfile($arguments_href);

  Desc: Parse the strain file using parse_seqfile function and
        load the results into the PhyGeCluster object

  Ret: None

  Args: A hash reference with the following key: strainfile

  Side_Effects: Die if the argument used is not a hash or if none 
                strainfile is detailed.

  Example: $phygecluster->load_strainfile($arguments_href);

=cut

sub load_strainfile {
    my $self = shift;
    my $arg_href = shift;

    my %strains = ();
    
    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARG. ERROR: $arg_href is not a hash reference.\n");
	}
	unless (defined $arg_href->{'strainfile'}) {
	    croak("ARG. ERROR: 'strainfile' is not defined for $arg_href.\n");
	}
	else {
	    my %strains = parse_strainfile($arg_href);
	    $self->set_strains(\%strains);
	}
    }
    else {
      	croak("ARG. ERROR: No arg. was used for load_strainfile function\n");
    }
}



#######################
## PARSING FUNCTIONS ##
#######################

=head2 parse_blastfile

  Usage: my %clusters = parse_blastfile($arguments_href);

  Desc: Parse the blast file using bioperl Bio::SearchIO
        Cluster the sequences based in clustervalues. 

  Ret: %cluster, a hash with keys=cluster_name and 
       value=Bio::Cluster::SequenceFamily object

  Args: A hash reference with the following keys: blastfile, blastformat,
        report_status, clustervalues and rootname.
        Permited clustervalues: evalue, expect, frac_identical, frac_conserved,
		                gaps, hsp_length,  num_conserved, 
                                num_identical, score, bits, percent_identity
        Aditional argument: max_cluster_members

  Side_Effects: Die if the argument used is not a hash, if none 
                blastfile is detailed or if the clustervalues is not
                permitted
                blastformat = 'blasttable' by default.
                clustervalues = { percent_identity => ['>', 90'], 
                                  hsp_length       => ['>', 60'] }
                rootname = 'cluster'
                Print status messages with $arg_href->{'report_status'}
                Calculate the percent_identity as frac_identical * 100
                instead to use percent_identity from the blast result
                (it is a Bio::SearchIO

  Example: my %clusters = parse_blastfile($arguments_href);

=cut

sub parse_blastfile {
    my $arg_href = shift;
    
    my %clusters = ();
    my %cluster_members = ();
    my %pclusters = ();

    ## Define the permited blast variables according the 
    ## HSP methods

    my %blastvar = ( evalue              => 1,
		     expect              => 1,
		     frac_identical      => 1,
		     frac_conserved      => 1, 
		     gaps                => 1,
		     hsp_length          => 1,
		     num_conserved       => 1, 
		     num_identical       => 1,
		     score               => 1,
		     bits                => 1,
		     percent_identity    => 1,
		     max_cluster_members => 1,
	);


    ## Now parsing...

    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $arg_href is not a hash reference.\n");
	}
	unless (defined $arg_href->{'blastfile'}) {
	    croak("ARGUMENT ERROR: 'blastfile' isnot defined for $arg_href.\n");
	}
	else {
		
	    ## 0) Define default values
	    
	    unless (defined $arg_href->{'blastformat'}) {
		$arg_href->{'blastformat'} = 'blasttable';
	    }
	    unless (defined $arg_href->{'clustervalues'}) {
		$arg_href->{'clustervalues'} = { 
		    "percent_identity" => ['>', 90], 
		    "hsp_length"       => ['>', 60],
		};
	    }
	    else {
		foreach my $clval_key (keys %{$arg_href->{'clustervalues'}}) {
		    unless (exists $blastvar{$clval_key}) {
			my $er = "WRONG BLAST VARIABLE: $clval_key is not a ";
			$er .= "permited var. for parse_blast function.";
			croak($er);
		    }
		}
	    }

	    unless (defined $arg_href->{'rootname'}) {
		$arg_href->{'rootname'} = 'cluster';
	    }
	    
	    ## Get and delete max_cluster_members if exist


	    my $max_mb;
	    if (exists $arg_href->{clustervalues}->{max_cluster_members}) {
		$max_mb = delete($arg_href->{clustervalues}
				          ->{max_cluster_members});
	    }

	    ## 1) Parse the file and create the clusters
	    
	    my %clustervals = %{$arg_href->{'clustervalues'}};
	    
	    my $searchio = Bio::SearchIO->new( 
		-format => $arg_href->{'blastformat'}, 
		-file   => $arg_href->{'blastfile'}
		);
	    
	    my $ht = $searchio->result_count();
	    unless (defined $ht) {
		my $infile = $arg_href->{'blastfile'};
		$ht = `cut -f1 $infile | wc -l`;
		chomp($ht);
	    }
	    my $hc = 0;

	    ## define the last cluster n
			    
	    my $cluster_n = 0;

	    while( my $result = $searchio->next_result() ) {
		
		my $q_name = $result->query_name();		

		while( my $hit = $result->next_hit() ) {

		    $hc++;
		    my $s_name = $hit->name();
		    if (exists $arg_href->{'report_status'}) {
			print_parsing_status($hc, $ht, 
					   "Percentage of blast file parsed:");
		    }
		    
		    while( my $hsp = $hit->next_hsp() ) {

			## define the last cluster n
			    
			$cluster_n = scalar(keys(%pclusters));

			## Define the cluster name according the q_name
		
			my $cluster_name = $cluster_members{$q_name};
			my $member_n = 0;

			if (defined $cluster_name) {
			    if (exists $pclusters{$cluster_name}) {
				my @members = @{$pclusters{$cluster_name}};
				$member_n = scalar(@members);
			    }
			}

			    
			unless ($q_name eq $s_name) {
			    
			    ## define the conditions needed for be in 
			    ## a cluster.
			    my $conditions_n = scalar(keys(%clustervals));

			    foreach my $cluster_cond (keys %clustervals) {
				my $cutc = $clustervals{$cluster_cond};
				
				if (ref($cutc) ne 'ARRAY') {
				    my $er2 = "WRONG clustervalues format ";
				    $er2 .= "($cutc) for parse_blastfile()";
				    croak($er2);
				}
				
				my $cond = $clustervals{$cluster_cond}->[0];
				my $val = $clustervals{$cluster_cond}->[1];
				unless ($val =~ m/^\d+$/) {
				    my $er3 = "WRONG clustervalues val=";
				    $er3 .= "$cluster_cond only int. are ";
				    $er3 .= "permited for parse_blastfile()";
				    croak($er3);
				}
				    
				if ($cond =~ m/^<$/) {
				    if ($hsp->$cluster_cond < $val) {
					$conditions_n--;
				    }
				} 
				elsif ($cond =~ m/^<=$/) {
				    if ($hsp->$cluster_cond <= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^==$/) {
				    if ($hsp->$cluster_cond == $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>=$/) {
				    if ($hsp->$cluster_cond >= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>$/) {
				    if ($hsp->$cluster_cond > $val) {
					$conditions_n--;
				    }
				}
				else {
				    my $er4 = "WRONG clustervalues val=";
				    $er4 .= "$cluster_cond, it is not a ";
				    $er4 .= "permited condition ('<','<=',";
				    $er4 .= "'==','>=' or '>')\n";
				    croak($er4);
				}
			    }    
			    
			    ## Anyway if exists max cluster members and it is >
			    ## than that change conditions
			    
			    if (defined $max_mb) {
				if ($member_n >= $max_mb) {
				    $conditions_n = 1;
				}
			    }

			    unless (exists $cluster_members{$s_name}) {
				
				## New cluster condition, it will overwrite
				## the default cluster name 
				
				if ($conditions_n > 0) {
				    $cluster_name = $arg_href->{'rootname'} 
				    . '_' . ($cluster_n+1);
				}
				
				unless (exists $pclusters{$cluster_name}) {
				    $pclusters{$cluster_name} = [$s_name];
				}
				else {
				    push @{$pclusters{$cluster_name}}, 
				    $s_name;
				}
				$cluster_members{$s_name} = $cluster_name;
			    }
			}
			else {  
                       
			    ## Selfblast hit. It always will add that if it
			    ## has not added before as subject (s_name) hit

			    unless (exists $cluster_members{$q_name}) {
			    
				$cluster_name =  $arg_href->{'rootname'} . 
				    '_' . 
				    ($cluster_n+1);
				    
				unless (exists $pclusters{$cluster_name}) {
				    $pclusters{$cluster_name} = [$q_name];
				}
				else {
				    push @{$pclusters{$cluster_name}}, 
				    $q_name;
				}
				$cluster_members{$q_name} = $cluster_name;
			    }
			}
		    }		    
		}
	    }
	}
	if (exists $arg_href->{'report_status'}) {
			print "\n";
	}
    }
    else {
	croak("ARG. ERROR: No argument was used for parse_blast function\n");
    }

    ## Now it knows how many clusters there are, so it will change the names
    ## and the nre names to the new cluster hash

    my $cluster_n = scalar(keys %pclusters);
    my $name_l = length($cluster_n);

    my %clmemb = ();
    foreach my $cl_id (keys %pclusters) {
	my $memb_n = scalar(@{$pclusters{$cl_id}});
	$clmemb{$cl_id} = $memb_n;
    }
    
    my $n = 0;
    foreach my $clid (sort { $clmemb{$b} <=> $clmemb{$a} } keys %clmemb) {
	$n++;
	my $new_clid = $arg_href->{'rootname'}.'_'.sprintf('%0'.$name_l.'s',$n);

	my @seqs = ();
	foreach my $seq_id (@{$pclusters{$clid}}) {
	    my $seq = Bio::Seq->new(
		-id => $seq_id,
		);
	    push @seqs, $seq;
	}
	
	my $seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $new_clid,
	    -members   => \@seqs,
	    );
	$clusters{$new_clid} = $seqfam;
    } 
    return %clusters;
}

=head2 fastparse_blastfile

  Usage: my %clusters = fastparse_blastfile($arguments_href);

  Desc: Parse the blast file using its own script
        Cluster the sequences based in clustervalues

  Ret: %cluster, a hash with keys=cluster_name and 
       value=Bio::Cluster::SequenceFamily object

  Args: A hash reference with the following keys: blastfile, blastformat,
        report_status, clustervalues and rootname.
        Permited clustervalues: query_id, subject_id, percent_identity, 
                                align_length, mismatches, gaps_openings, 
                                q_start, q_end, s_start, s_end, e_value, 
                                bit_score.

        Aditional clustervalues: max_cluster_members

  Side_Effects: Die if the argument used is not a hash or if none 
                blastfile is detailed.
                Die if is using non permited clustervalues
                blastformat = 'blasttable' by default.
                clustervalues = { percent_identity => ['>', 90 ], 
                                  align_length     => ['>', 60 ],
                                  mismatches       => ['<', 25 ]}
                rootname = 'cluster'
                Print status messages with $arg_href->{'report_status'}

  Example: my %clusters = parse_blastfile($arguments_href);

=cut

sub fastparse_blastfile {
    my $arg_href = shift;
    
    my %clusters = ();
    my %cluster_members = ();
    my %pclusters = ();

    ## Define the possible clustervalues

    my %blastvar = (
	            'query_id'            => 0, 
		    'subject_id'          => 1, 
		    'percent_identity'    => 2, 
		    'align_length'        => 3,
		    'mismatches'          => 4, 
		    'gaps_openings'       => 5,
		    'q_start'             => 6,
		    'q_end'               => 7, 
		    's_start'             => 8, 
		    's_end'               => 9,
		    'e_value'             => 10,
		    'bit_score'           => 11,
                    'max_cluster_members' => 12,
	);

    ## Now parsing...

    if (defined $arg_href) {
	
	if (ref($arg_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $arg_href is not a hash reference.\n");
	}

	unless (defined $arg_href->{'blastfile'}) {
	    croak("ARGUMENT ERROR: 'blastfile' isnot defined for $arg_href.\n");
	}
	else {

	    ## Check fastblastparser compatibilities
	    my $bl_format = $arg_href->{'blastformat'};
	    if (defined $bl_format && $bl_format !~ m/m8|blasttable/) {
		my $er0 = "ARG. ERROR: fastparse_blastfile function only ";
		$er0 .= "can be used with blasttable or m8 formats";
		croak($er0);
	    }
	    
		
	    ## 0) Define default values

	    unless (defined $arg_href->{'clustervalues'}) {
		$arg_href->{'clustervalues'} = { 
		    "percent_identity" => ['>', 90], 
		    "align_length"     => ['>', 60],
		};
	    }
	    else {
		foreach my $clval_key (keys %{$arg_href->{'clustervalues'}}) {
		    unless (exists $blastvar{$clval_key}) {
			my $er = "WRONG BLAST VARIABLE: $clval_key is not a ";
			$er .= "permited var. for fastparse_blast function.";
			croak($er);
		    }
		}
	    }
	    unless (defined $arg_href->{'rootname'}) {
		$arg_href->{'rootname'} = 'cluster';
	    }
	    
	    my $max_mb;
	    if (exists $arg_href->{clustervalues}->{max_cluster_members}) {
		$max_mb = delete($arg_href->{clustervalues}
				          ->{max_cluster_members});
	    }

	    ## 1) Parse the file and create the clusters
	    
	    my %clustervals = %{$arg_href->{'clustervalues'}};
	    
	    my $infile = $arg_href->{'blastfile'};
	    
	    my $ht = `cut -f1 $infile | wc -l`;
	    chomp($ht);
	    my $hc = 0;

	    open my $in, '<', $infile;

	    while(<$in>) {
		chomp($_);
		$hc++;

		my %datap = ();
		my @data = split(/\t/, $_);
		foreach my $field (sort {$blastvar{$a} <=> $blastvar{$b}} 
				   keys(%blastvar) ) {

		    $datap{$field} = $data[$blastvar{$field}];
		}

		my $q_name = $datap{'query_id'};
		my $s_name = $datap{'subject_id'};
		
		## define the last cluster n
		
		my $cluster_n = scalar(keys(%pclusters));

		## Define the cluster name according the q_name
		
		my $cluster_name = $cluster_members{$q_name};
		
		my $member_n = 0;
		if (defined $cluster_name) {
		    $member_n = scalar(@{$pclusters{$cluster_name}});
		}


		if (exists $arg_href->{'report_status'}) {
		    print_parsing_status($hc, $ht, 
					 "Percentage of blast file parsed:");
		}
		    
		unless ($q_name eq $s_name) {
		    
		    ## define the conditions needed for be in 
		    ## a cluster.
		    my $conditions_n = scalar(keys(%clustervals));
			
		    foreach my $cluster_cond (keys %clustervals) {
			my $cutc = $clustervals{$cluster_cond};
			if (ref($cutc) ne 'ARRAY') {
			    my $er2 = "WRONG clustervalues format ";
			    $er2 .= "($cutc) for parse_blastfile()";
			    croak($er2);
			}

			my $cond = $clustervals{$cluster_cond}->[0];
			my $val = $clustervals{$cluster_cond}->[1];
			unless ($val =~ m/^\d+$/) {
			    my $er3 = "WRONG clustervalues val=$cluster_cond";
			    $er3 .= "only int. are permited parse_blastfile()";
			    croak($er3);
			}


			if ($cond =~ m/^<$/) {
			    if ($datap{$cluster_cond} < $val) {
				$conditions_n--;
			    }
			} 
			elsif ($cond =~ m/^<=$/) {
			    if ($datap{$cluster_cond} <= $val) {
				$conditions_n--;
			    }
			}
			elsif ($cond =~ m/^==$/) {
			    if ($datap{$cluster_cond} == $val) {
				$conditions_n--;
			    }
			}
			elsif ($cond =~ m/^>=$/) {
			    if ($datap{$cluster_cond} >= $val) {
				$conditions_n--;
			    }
			}
			elsif ($cond =~ m/^>$/) {
			    if ($datap{$cluster_cond} > $val) {
				$conditions_n--;
			    }
			}
			else {
			    my $er4 = "WRONG clustervalues val=";
			    $er4 .= "$cluster_cond, it is not a ";
			    $er4 .= "permited condition ('<','<=',";
			    $er4 .= "'==','>=' or '>')\n";
			    croak($er4);
			}
		    }
		    
		    ## Anyway if exists max cluster members and it is >
                    ## than that change conditions                      

		    if (defined $max_mb) {
			if ($member_n >= $max_mb) {
			    $conditions_n = 1;
			}
		    }
			    
		    unless (exists $cluster_members{$s_name}) {
				
			## New cluster condition, it will overwrite the
			## default cluster name 

			if ($conditions_n > 0) {
			    $cluster_name =  $arg_href->{'rootname'} . 
				'_' . 
				($cluster_n+1);
			}
			else {
			    unless (exists $cluster_members{$q_name}) {
		    
				$cluster_name =  $arg_href->{'rootname'} . 
				    '_' . 
				    ($cluster_n+1);
			    }
			}

			unless (exists $pclusters{$cluster_name}) {
			    $pclusters{$cluster_name} = [$s_name];
			}
			else {
			    push @{$pclusters{$cluster_name}}, $s_name;
			}
			$cluster_members{$s_name} = $cluster_name;
		    }
		}
		else {  
		
		    ## Selfblast hit. It always will add that if it has not
		    ## added before as subject (s_name) hit
		
		    unless (exists $cluster_members{$q_name}) {
		    
			$cluster_name =  $arg_href->{'rootname'} . 
			    '_' . 
			    ($cluster_n+1);

			unless (exists $pclusters{$cluster_name}) {
			    $pclusters{$cluster_name} = [$q_name];
			}
			else {
			    push @{$pclusters{$cluster_name}}, $q_name;
			}
			$cluster_members{$q_name} = $cluster_name;
		    }
		}
	    }
	    close $in;
	    if (exists $arg_href->{'report_status'}) {
		print "\n";
	    }
	}
    }
    else {
	croak("ARG. ERROR: No argument was used for parse_blast function\n");
    }

    ## Finally it will convert all the cluster data into key=cluster_id and
    ## value=Bio::Cluster::SequenceFamily object

    ## Now it knows how many clusters there are, so it will change the names
    ## and the nre names to the new cluster hash

    my $cluster_n = scalar(keys %pclusters);
    my $name_l = length($cluster_n);

    my %clmemb = ();
    foreach my $cl_id (keys %pclusters) {
	my $memb_n = scalar(@{$pclusters{$cl_id}});
	$clmemb{$cl_id} = $memb_n;
    }
    
    my $n = 0;
    foreach my $clid (sort { $clmemb{$b} <=> $clmemb{$a} } keys %clmemb) {
	$n++;
	my $new_clid = $arg_href->{'rootname'}.'_'.sprintf('%0'.$name_l.'s',$n);

	my @seqs = ();
	foreach my $seq_id (@{$pclusters{$clid}}) {
	    my $seq = Bio::Seq->new(
		-id => $seq_id,
		);
	    push @seqs, $seq;
	}
	
	my $seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $new_clid,
	    -members   => \@seqs,
	    );
	$clusters{$new_clid} = $seqfam;
    } 
    return %clusters;
}



=head2 parse_seqfile

  Usage: my %seqs = parse_seqfile($arguments_href);

  Desc: Parse the fasta file using bioperl Bio::SeqIO
        and return a hash with keys=seq_id and values=seqobjs

  Ret: %seqs, a hash with keys=seq_id and value= with
       sequences ids.

  Args: A hash reference with the following keys: sequencefile,
        report_status

  Side_Effects: Die if the argument used is not a hash.
                Print status messages with $arg_href->{'debug'}

  Example: my %seqs = parse_seqfile($arguments_href);

=cut

sub parse_seqfile {
    my $args_href = shift;
    
    my %seqs = ();
    
    if (defined $args_href) {
	if (ref($args_href) ne 'HASH') {
	    croak("ARG. ERROR: $args_href is not a hash reference.\n");
	}
	unless (defined $args_href->{'sequencefile'}) {
	    croak("ARG. ERROR: 'sequencefile' is not defined for $args_href\n");
	}
	else {

	    my $seqfile = $args_href->{'sequencefile'};
	    my $seqio = Bio::SeqIO->new(-format => 'fasta', 
					-file => $seqfile );
	    
	    
	    my $st = `grep -c '>' $seqfile`;
	    chomp($st);
	    my $sc = 0;
	    
	    while((my $seqobj = $seqio->next_seq())) {
		
		$sc++;
		my $seqid = $seqobj->display_id();
		$seqs{$seqid} = $seqobj;
		if (exists $args_href->{'report_status'}) {
		    print_parsing_status($sc, $st, 
					 "Percentage of seq file parsed:");
		}
	    }
	    if (exists $args_href->{'report_status'}) {
		print "\n";
	    }
	}
    }
    else {
      	croak("ARG. ERROR: No argument was used for parse_seqfile function\n");
    }
    
    return %seqs;
}




=head2 parse_strainfile

  Usage: my %strains = parse_strainfile($arguments_href);

  Desc: Parse the strain file and return a hash with keys=seq_id 
        and values=strain

  Ret: %strain, a hash with keys=seq_id and value= strain

  Args: A hash reference with the following keys: strainfile, report_status

  Side_Effects: Die if the argument used is not a hash.
                Die if the if do not exists $args{'strainfile'}
                Print status messages with $arg_href->{'report_status'}

  Example: my %strain = parse_strainfile($arguments_href);

=cut

sub parse_strainfile {
    my $arg_href = shift;
    
    my %strains = ();
    
    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARG. ERROR: $arg_href is not a hash reference.\n");
	}
	unless (defined $arg_href->{'strainfile'}) {
	    croak("ARG. ERROR: 'strainfile' is not defined for $arg_href.\n");
	}
	else {
	    open my $fileio, '<', $arg_href->{'strainfile'};
	    my $st = `cut -f1 $arg_href->{'strainfile'} | wc -l`;
	    chomp($st);
	    my $sc = 0;

	    while(<$fileio>) {
		chomp($_);
		$sc++;
		my @cols = split('\t', $_);
		$strains{$cols[0]} = $cols[1];
		if (exists $arg_href->{'report_status'}) {
		    print_parsing_status($sc, $st, 
					 "Percentage of strain file parsed:");
		}
	    }
	    close $fileio;
	    if (exists $arg_href->{'report_status'}) {
		print "\n";
	    }
	}
    }
    else {
      	croak("ARG. ERROR: No arg. was used for parse_strainfile function\n");
    }
    
    return %strains;
}

=head2 parse_acefile

  Usage: my %clusters = parse_acefile($arguments_href);

  Desc: Parse partially an assembly file for .ace format and return a
        hash with keys=contig_id and value=Bio::Cluster::SequenceFamily object

  Ret: A hash with keys=contig_id and value=Bio::Cluster::SequenceFamily

  Args: A hash reference with the following keys: acefile, report_status

  Side_Effects: Die if the argument used is not a hash.
                Die if the if do not exists $args{'acefile'}
                Print status messages with $arg_href->{'report_status'}

  Example: my %clusters = parse_acefile($arguments_href);

=cut

sub parse_acefile {
    my $arg_href = shift;
    
    ## Check variables

    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARG. ERROR: $arg_href isn't a hash ref. for parse_acefile");
	}
    }
    else {
	croak("ARG. ERROR: No argument was used for parse_acefile function");
    }

    ## Define the variables

    my %clusters = ();

    my $acefile = $arg_href->{'acefile'} ||
	croak("ARG. ERROR: 'acefile' isn't defined for $arg_href.\n");
    
    my $nosinglets =  1;
    if (defined $arg_href->{'nosinglets'}) {
	if( $arg_href->{'nosinglets'} =~ m/^(0|N)/i) {
	    $nosinglets = 0;
	}
    }

    my $L = `cut -f1 $acefile | wc -l`;
    chomp($L);
    my $l = 0;
    
    ## Define the catching variables
    
    my $curr_cr = '';
    my $contig_id = '';
    my $read_id = '';
    my %contigs = ();
    my %reads = ();

    ## Counting vars:

    my ($contigs_n, $reads_n) = (0, 0);

    ## Open the file

    open my $ifh, '<', $acefile;
   
    while(<$ifh>) {
	chomp($_);
	$l++;

	if (exists $arg_href->{'report_status'}) {
	    my $contig_c = scalar(keys %contigs);
	    print_parsing_status($l, $L, 
				 "Percentage of ace file parsed:");
	}
	
	if ($_ =~ m/^([A-Z][A-Z]) /) {
	    $curr_cr = $1;
	}
	elsif ($_ =~ m/^$/) {
	    $curr_cr = '';
	}
	
	if ($curr_cr eq 'AS') {
	    if ($_ =~ m/^AS\s+(\d+)\s+(\d+)/) {
		$contigs_n = $1;
		$reads_n = $2;
	    }
	}
	if ($curr_cr eq 'CO') {
	    if ($_ =~ m/^CO\s+(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\w)/) {
		$contig_id = $1;

		$contigs{$contig_id} = { 'bases_num'    => $2, 
					 'reads_num'    => $3,
					 'base_segm'    => $4,
					 'complemenent' => $5,
					 'seq'          => '',
					 'rd_members'   => {},
		};
		$reads{$contig_id} = {};
	    }
	    else {
		$contigs{$contig_id}->{'seq'} .= $_;
	    }
	}
	if ($curr_cr eq 'AF') {
	    if ($_ =~ m/^AF\s+(.+?)\s+(\w)\s+(-?\d+)/) {
		$read_id = $1;
		$reads{$contig_id}->{$read_id} = { 'complemenent'        => $2,
						   'pad_start_consensus' => $3,
						   'pad_bases_num'       => '',
						   'seq'                 => '',
						   'qual_clip_start'     => '',
						   'qual_clip_end'       => '',
						   'align_clip_start'    => '',
						   'align_clip_end'      => '',
		};
		unless (exists $contigs{$contig_id}->{rd_members}->{$read_id}) {
		    $contigs{$contig_id}->{rd_members}->{$read_id} = 1;
		}
	    }  	    
	}
	if ($curr_cr eq 'RD') {
	    if ($_ =~ m/^RD\s+(.+?)\s+(\d+)\s+(\d+)\s+(\d+)/) {
		$read_id = $1;
		if (exists $reads{$contig_id}->{$read_id}) {
		    $reads{$contig_id}->{$read_id}->{'pad_bases_num'} = $2;
		#    print STDERR "\n\nWARNING: $read_id exists in multiple ";
		#    print STDERR "contigs. It could produce an error in the ";
		#    print STDERR "alignment creation.\n\n";
		}
		else {
		    $reads{$contig_id}->{$read_id} = { 
			'complemenent'        => '',
			'pad_start_consensus' => '',
			'pad_bases_num'       => $2,
			'seq'                 => '',
			'qual_clip_start'     => '',
			'qual_clip_end'       => '',
			'align_clip_start'    => '',
			'align_clip_end'      => '',
		    };
		}
		unless (exists $contigs{$contig_id}->{rd_members}->{$read_id}) {
		    $contigs{$contig_id}->{rd_members}->{$read_id} = 1;
		}
	    }
	    else {
		$reads{$contig_id}->{$read_id}->{'seq'} .= $_;
	    }
	}
	if ($curr_cr eq 'QA') {
	    if ($_ =~ m/^QA\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/) {

		$reads{$contig_id}->{$read_id}->{'qual_clip_start'} = $1;
		$reads{$contig_id}->{$read_id}->{'qual_clip_end'} = $2;
		$reads{$contig_id}->{$read_id}->{'align_clip_start'} = $3;
		$reads{$contig_id}->{$read_id}->{'align_clip_end'} = $4;

		my $seqobj = Bio::Seq->new( -id  => $read_id,
					    -seq => $reads{$contig_id}->
					    {$read_id}->{'seq'},
		    );

		## To get the trim sequence, remenber that .ace files are
		## 1-based and bioperl is 1-based. The end position will
		## be length+1 (for example 1nt length will be 1-2)

		my $st = $reads{$contig_id}->{$read_id}->{'align_clip_start'};
		my $en = $reads{$contig_id}->{$read_id}->{'align_clip_end'};
		my $cs = $reads{$contig_id}->{$read_id}
		                           ->{'pad_start_consensus'};

		my $le = $en - $st;
		my $ce = $en + $cs - 1;

		my $init_gaps = '';
		my $final_gaps = '';
		my $finalseq = '';
		if ($cs =~ m/^-(\d+)/) {
		    $st = $1 + 2;
		    $reads{$contig_id}->{$read_id}->{'pad_start_consensus'} = 1;
		}
		else {
		
		    ## It will add as many gaps signs before the sequence as 
		    ## pad_start_consensus - 1.
		    if ($cs >= 0) {
			foreach my $i (1 .. $cs + $st - 2) {
			    $finalseq .= '-';
			}
		    }
		}
		
		$finalseq .= $seqobj->subseq($st, $en);
		my $final_l = length($finalseq);

		my $co_en = $contigs{$contig_id}->{'bases_num'};
		while ($final_l < $co_en) {
		    $finalseq .= '-';
		    $final_l = length($finalseq);
		}
		
		$reads{$contig_id}->{$read_id}->{'trimseq'} = $finalseq;

	        $reads{$contig_id}->{$read_id}->{'trimseq'} =~ s/\*/-/g;
		my $unpadseq = $reads{$contig_id}->{$read_id}->{'trimseq'};
		$unpadseq =~ s/-//g;
		$reads{$contig_id}->{$read_id}->{'unpadseq'} = $unpadseq
	    }
	}
    }

    ## Now it will build the clusters with the sequences.

    foreach my $ctg_id (keys %contigs) {
	my %contig_data = %{$contigs{$ctg_id}};
	my %members = %{$contig_data{'rd_members'}};

	## First, create the array with Bio::Seq::Meta objects with all
	## the sequence members.

	## SKIP when only one member is present (singlets)

	if (scalar(keys %members) > 1 || $nosinglets == 0) { 

	    my @align_objs = ();
	    my @member_objs = ();
	    foreach my $memb_id (keys %members) {
		my %rd = %{$reads{$ctg_id}->{$memb_id}};
		my $strand = 1;
		if ($rd{'complemenent'} eq 'C') {
		    $strand = -1;
		}
	    
		my $seq = Bio::Seq->new( -id  => $memb_id, 
					 -seq => $rd{'unpadseq'} );
		push @member_objs, $seq;

		my $metaseq = Bio::LocatableSeq->new( 
		    -id     => $memb_id,
		    -start  => $rd{'pad_start_consensus'},
		    -end    => 
		    $rd{'pad_start_consensus'}+length($rd{'unpadseq'})-1,
		    -strand => $strand,
		    -seq    => $rd{'trimseq'},
		    -verbose => 0,
		    );
		push @align_objs, $metaseq;
	    }

	    ## Second, create the Bio::Align object.
	    
	    my $cons_seq = Bio::Seq::Meta->new( 
		-id  => $ctg_id,
		-seq => $contigs{$ctg_id}->{'seq'},
		);

	    my $align = Bio::SimpleAlign->new( -id        => $ctg_id, 
					       -source    => 
					       '.ace, assembly file',
					       -seqs      => \@align_objs,
					       -consensus_meta => $cons_seq, 
		);

	    ## Create a Bio::Cluster::SequenceFamily object and load the 
	    ## alignment

	    my $seqfam = Bio::Cluster::SequenceFamily->new(
		-family_id => $ctg_id, 
		-members   => \@member_objs,	    
		);
	    $seqfam->alignment($align),
	
	    $clusters{$ctg_id} = $seqfam;
	}
    }
    return %clusters;
}

######################
## OUTPUT FUNCTIONS ##
######################

=head2 print_parsing_status

  Usage: print_parsing_status($progress, $total, $message, $id);

  Desc: Print as STDERR the percentage of the file parsed

  Ret: none

  Args: $progress, a scalar, an integer with the progress
        $total, a scalar, a integer with the total
        $message to print before the percentage
        $id, to print after the percetage

  Side_Effects: Die if 1st and 2nd arguments are undefined or are not integers
                Print as default message: Percentage of the file parsed: ";

  Example: print_parsing_status($progress, $total, $message);

=cut

sub print_parsing_status {
    my $a = shift;

    unless (defined $a) {
	croak("ERROR: 1st argument is not defined for print_parsing_status()");
    }
    my $z = shift;
    
    unless (defined $z) {
	croak("ERROR: 2nd argument is not defined for print_parsing_status()");
    }
	
    my $message = shift ||
	"Percentage of the file parsed:";

    my $id = shift || 'NA';

    unless ($a =~ m/^\d+$/) {
	croak("ERROR: 1st argument is not an int. for print_parsing_status()");
    }
    unless ($z =~ m/^\d+$/) {
	croak("ERROR: 2nd argument is not an int. for print_parsing_status()");
    }
    
    my $perc = $a * 100 / $z;
    my $perc_obj = Math::BigFloat->new($perc);
    my $perc_formated = $perc_obj->bfround(-2);

    print STDERR "\t$message $perc_formated %    \t(processing:$id)       \r";
}

=head2 out_clusterfile

  Usage: my %files = $phygecluster->out_clusterfile(\%args);

  Desc: Print into one or more files the clusters members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('clustercomp' by default),
         distribution => $distribution (two options: single or multiple)

  Side_Effects: None

  Example: my %files = $phygecluster->out_clusterfile({ 
                                                       distribution => single});

=cut

sub out_clusterfile {
    my $self = shift;
    my $argshref = shift;

    ## Check variables and complete with default arguments

    my $def_argshref = { rootname     => 'clustercomp', 
			 distribution => 'multiple',
			 summary      => 1,
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_clusterfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_clusterfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %clusters = %{$self->get_clusters()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    my $sum_fh;
    if (defined $argshref->{'summary'} && $argshref->{'summary'} =~ m/^(1|Y)/) {
	my $sum_filename = $argshref->{'rootname'} . '.summary.txt';
	$outfiles{summary} = $sum_filename;
	open $sum_fh, '>', $sum_filename;
    }


    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . '.multiplecluster.txt';
	open my $outfh1, '>', $outname1;
	$outfiles{'multiple'} = $outname1;
	
	foreach my $cluster_id (sort keys %clusters) {
	    my @members = $clusters{$cluster_id}->get_members();
	    my $memb_n = scalar(@members);

	    if (defined $sum_fh) {
		print $sum_fh "$cluster_id\t$memb_n\n";
	    }
	    
	    foreach my $member (sort @members) {
		my $member_id = $member->display_id();
		print $outfh1 "$cluster_id\t$member_id\n";
	    }
	}	
	close $outfh1;	
    }
    else {
	foreach my $cluster_id (sort keys %clusters) {
	    my $outname2 = $argshref->{'rootname'} . '.' . $cluster_id  .'.txt';
	    open my $outfh2, '>', $outname2;
	    $outfiles{$cluster_id} = $outname2;
	    
	    my @members = $clusters{$cluster_id}->get_members();
	    my $memb_n = scalar(@members);

	    if (defined $sum_fh) {
		print $sum_fh "$cluster_id\t$memb_n\n";
	    }

	    foreach my $member (sort @members) {
		my $member_id = $member->display_id();
		print $outfh2 "$cluster_id\t$member_id\n";
	    }
	    close $outfh2;
	}
    }

    if (defined $sum_fh) {
	close($sum_fh);
    }

    return %outfiles;
}

=head2 out_alignfile
    
  Usage: my %files = $phygecluster->out_alignfile(\%args);

  Desc: Print into one or more files the alignment of the cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
    and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('alignment' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (bl2seq, clustalw, emboss, fasta, maf, mase,
                                  mega, meme, metafasta, msf, nexus, pfam, 
                                  phylip, po, prodom, psi, selex, stockholm,
                                  XMFA, arp)
                         (see bioperl Bio::AlignIO for more details)
                         ('clustalw' by default)
         extension    => $fileextension ('aln' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_alignfile();

=cut

sub out_alignfile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { 'rootname'     => 'alignment', 
			 'distribution' => 'multiple',			 
			 'format'       => 'clustalw',
                         'extension'    => 'aln',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %clusters = %{$self->get_clusters()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multiplealignments.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $alignio1 = Bio::AlignIO->new( -format => $argshref->{'format'},
                                          -file   => ">$outname1",
                                        );

	foreach my $cluster_id (sort keys %clusters) {
    
	    my $align = $clusters{$cluster_id}->alignment();
            if (defined $align) {
                $alignio1->write_aln($align);
            }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %clusters) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    $outfiles{$cluster_id} = $outname2;
	    
	    my $alignio2 = Bio::AlignIO->new( -format => $argshref->{'format'},
                                              -file   => ">$outname2",
                                            );

            my $align = $clusters{$cluster_id}->alignment();
            if (defined $align) {
                $alignio2->write_aln($align);
            }
	}
    }

    return %outfiles;
}

=head2 out_alignstats
    
  Usage: my $statfile = $phygecluster->out_alignstats($basename);

  Desc: Print into one file the summary of the stats file as the following
        columns:
        <cluster_id>
        <member_count>
        <align_length>
        <align_ident_average>
        <composition_by_strain>
        <members_ids>

  Ret: $statsfile, a filename

  Args: $basename, a basename for the new file.

  Side_Effects: Use a default basename of 'alignstats.tab'

  Example: my $stats = $phygecluster->out_alignstats();

=cut

sub out_alignstats {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { 'basename' => 'alignstats.tab' };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignstats");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignstats");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my $filestats =  $argshref->{'basename'};
    open my $stfh, '>', $filestats;

    ## Get the clusters and the alignments.

    my %clusters = %{$self->get_clusters()};
    my %strains = %{$self->get_strains()};

    foreach my $cluster_id (sort keys %clusters) {

	my @line = ($cluster_id);

	my $align = $clusters{$cluster_id}->alignment();	    
	if (defined $align && ref($align) eq 'Bio::SimpleAlign') {
	    
	    my @members = $align->each_seq();
	    my @members_ids = ();

	    push @line, scalar(@members);              ## Add member number
	    push @line, $align->length();              ## Add align length

	    my $idperc = $align->percentage_identity();
	    my $idperc_obj = Math::BigFloat->new($idperc);
	    push @line, $idperc_obj->bfround(-2);        ## Add ident.% rounded
	    
	    my %comp = ();                             ## Get composition
	    foreach my $seq (@members) {
		push @members_ids, $seq->id();
		my $str = $strains{$seq->id()} || 'NA';
		if (exists $comp{$str}) {
		    $comp{$str}++;
		}
		else {
		    $comp{$str} = 1;
		}
	    }
	    my @compline = ();
	    foreach my $strkey (sort keys %comp) {
		push @compline, $strkey . '=' . $comp{$strkey};
	    }
	    push @line, join(',', @compline);          ## Add composition.
	    push @line, join(',', sort @members_ids);  ## Add members
	}
	else {
	    push @line, ('NA', 'NA', 'NA', 'NA', 'NA');
	}
	my $line = join("\t", @line);
	print $stfh "$line\n";
    }	
    close($stfh);
    
    return $filestats;
}


=head2 out_bootstrapfile
    
  Usage: my %files = $phygecluster->out_bootstrapfile(\%args);

  Desc: Print into one or more files the bootstrap for the alignment of the 
        cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('alignment' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (depending for the type:
                         * consensus => newick, nexus
         extension    => $fileextension ('aln' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_bootstrapfile();

=cut

sub out_bootstrapfile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { 'rootname'     => 'bootstrap',
			 'distribution' => 'single',			 
			 'format'       => 'newick',
                         'extension'    => 'txt',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Catch the type

    my $type = $argshref->{'type'};

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %bootstrap = %{$self->get_bootstrapping()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multiple_bootstrapping.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $consensusio = Bio::TreeIO->new( -format => $argshref->{'format'}, 
					    -file   => ">$outname1",
	    );

	foreach my $cluster_id (sort keys %bootstrap) {
	    
	    my $consensus = $bootstrap{$cluster_id};
	   
	    if (defined $consensus) {
		$consensusio->write_tree($consensus);
	    }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %bootstrap) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    my $phygeboots = $bootstrap{$cluster_id};
	    
	  
	    my $consenio = Bio::TreeIO->new( -format => $argshref->{'format'}, 
					     -file   => ">$outname2",
		);

	    my $consensus = $bootstrap{$cluster_id};
	    if (defined $consensus) {
		$consenio->write_tree($consensus);
		$outfiles{$cluster_id} = $outname2;
	    }
	}
    }

    return %outfiles;
}


=head2 out_distancefile
    
  Usage: my %files = $phygecluster->out_distancefile(\%args);

  Desc: Print into one or more files the distance of the cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('distance' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (mlagan, phylip)
                         (see bioperl Bio::MatrixIO for more details)
                         ('phylip' by default)
         extension    => $fileextension ('txt' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_distancefile();

=cut

sub out_distancefile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { rootname     => 'distance', 
			 distribution => 'multiple',
			 format       => 'phylip',
			 extension    => 'txt',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %distances = %{$self->get_distances()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multipledistances.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $matrixio1 = Bio::Matrix::IO->new( -format => $argshref->{'format'},
                                              -file   => ">$outname1",
                                        );

	foreach my $cluster_id (sort keys %distances) {
            if (defined $distances{$cluster_id}) {
                my $rowcount = $distances{$cluster_id}->num_rows();
                if ($rowcount > 1) {
                       $matrixio1->write_matrix($distances{$cluster_id});
                }
            }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %distances) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    
	    
	    if (defined $distances{$cluster_id}) {
                my $rowcount = $distances{$cluster_id}->num_rows();
                if ($rowcount > 1) {
		       my $matrixio2 = Bio::Matrix::IO->new( 
		                  -format => $argshref->{'format'},
		                  -file   => ">$outname2",
		       );
                              
                       $matrixio2->write_matrix($distances{$cluster_id});

                       $outfiles{$cluster_id} = $outname2;
                }
	    }
	}
    }

    return %outfiles;
}


=head2 out_treefile
    
  Usage: my %files = $phygecluster->out_treefile(\%args);

  Desc: Print into one or more files the tree of the cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('tree' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (newick,nexus,nhx,svggraph,tabtree,lintree)
                         (see bioperl Bio::TreeIO for more details)
                         ('newick' by default)
         extension    => $fileextension ('txt' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_treefile();

=cut

sub out_treefile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { rootname     => 'tree', 
			 distribution => 'multiple',
			 format       => 'newick',
			 extension    => 'txt',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %seqfams = %{$self->get_clusters()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multipletrees.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $treeio1 = Bio::TreeIO->new( -format => $argshref->{'format'},
                                        -file   => ">$outname1",
                                        );

	foreach my $cluster_id (sort keys %seqfams) {
            if (defined $seqfams{$cluster_id}) {
                my $tree = $seqfams{$cluster_id}->tree();
                if (defined $tree) {
                    $treeio1->write_tree($tree);
                }
            }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %seqfams) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    $outfiles{$cluster_id} = $outname2;
	    
	    if (defined $seqfams{$cluster_id}) {
                my $tree = $seqfams{$cluster_id}->tree();
                if (defined $tree) {
                    my $treeio1 = Bio::TreeIO->new( 
                                        -format => $argshref->{'format'},
                                        -file   => ">$outname2",
                                        );

                    $treeio1->write_tree($tree);
                }
	    }
	}
    }

    return %outfiles;
}



##########################
## ANALYTICAL FUNCTIONS ##
##########################

=head2 cluster_sizes

  Usage: my %cluster_sizes = phygecluster->cluster_sizes();
         my %cluster_sizes = phygecluster->cluster_sizes($min, $max);

  Desc: return a hash with keys=cluster_id and values=size

  Ret: %cluster_sizes,  with keys=cluster_id and values=size

  Args: $min, $max values to select the sizes ($min <= $size <= $max)

  Side_Effects: If $min value is detailed but $max value is absent, 
                $max = $min.
                If there are not any cluster with the size requeriments,
                it will return undef

  Example: my %cluster_sizes = phygecluster->cluster_sizes();
           my %singlets = phygecluster->cluster_sizes(1,1);
=cut

sub cluster_sizes {
    my $self = shift;
    my $min = shift;
    my $max = shift;

    if ($min && !$max) {
	$max = $min;
    }

    my %cluster_sizes = ();

    my %clusters = %{$self->get_clusters()};
    my $CL = scalar(keys %clusters);
    my $cl = 0;

    foreach my $cluster_name (keys %clusters) {
	my $size = $clusters{$cluster_name}->size();

	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($cl, $CL, 
				 "\t\tPercentage of clusters sizes analyzed:",
				 $cluster_name,
		);
	}

	if (defined $min) {
	    if ($min <= $size && $size <= $max) {
		$cluster_sizes{$cluster_name} = $size;
	    }
	}
	else {
	    $cluster_sizes{$cluster_name} = $size;
	}
    }

    return %cluster_sizes;
}


=head2 calculate_overlaps

  Usage: my %overlaps = $phygecluster->calculate_overlaps();

  Desc: Calculate the overlap positions for each pair of sequences in an 
        alignment and return a hash with key=cluster_id and 
        value=Bio::Matrix::Generic with member_ids as columns and row names.
        The matrix will have as element { start => $val1, end => $val2, 
        length => $val3, ident => $val4 }

  Ret: %hash = ( $cluster_id => Bio::Matrix::Generic object );   

  Args: None

  Side_Effects: Return overlaps only for clusters with alignments

  Example: my %overlaps = phygecluster->calculate_overlaps();
           

=cut

sub calculate_overlaps {
    my $self = shift;    

    my %overlaps = ();
    my %clusters = %{$self->get_clusters()};
    my $CL = scalar( keys %clusters);
    my $cl = 0;

    open my $tfh, '>', 'testoverlaps.tab';

    foreach my $cluster_id (sort keys %clusters) {
	my $align = $clusters{$cluster_id}->alignment();
	my @members = ();

	if (defined $align && ref($align) eq 'Bio::SimpleAlign') {
	    @members = $align->each_seq();
	}	    

	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($cl, $CL, 
				 "\t\tPercentage of cluster overlaps analyzed:",
				 $cluster_id,
		);
	}

	if (scalar(@members) > 1) {

	    ## Get the member ids to create the empty matrix, and get also
	    ## the start and the end of each sequence.
	    
	    my %post = ();
	    my %seqobjs = ();
	    my @member_ids = ();
	    foreach my $seq (@members) {
		my $id = $seq->display_id();
		$seqobjs{$id} = $seq;
		
		push @member_ids, $id;

		my $seqstr = $seq->seq();
		my @nts = split(//, $seqstr);
		my ($pos, $start, $end) = (0, 0, 0);
		foreach my $nt (@nts) {
		    $pos++;
		    if ($nt !~ m/(-|\*|\.)/) {  ## If it is not a gap
			if ($start == 0) {
			    $start = $pos;
			}
			$end = 0;
		    }
		    else {
			if ($start > 0 && $end == 0) {
			    $end = $pos - 1;
			}
		    }
		}
		if ($end == 0) {
		    $end = $pos;
		}

		$post{$id} = [$start, $end, $end-$start];
	    }

	    my $default_vals = {start => 0, end => 0, length => 0, ident => 0};

	    ## Create the matrix with the member ids.
	    my $matrix = Bio::Matrix::Generic->new( 
		-rownames          => \@member_ids,
		-colnames          => \@member_ids, 
		-matrix_id         => $cluster_id,
		-matrix_init_value => $default_vals,
		);

	    ## Now it will compare pairs of sequences to get the 
	    ## overlapping region. There are four posibilities:
	    ## 1) As <= Bs; As < Be; Ae > Bs; --> Overlap St=Bs;En=Ae
	    ## 2) As >= Bs; As < Be; Ae > Bs; --> Overlap St=As;En=Be
	    ## 3) As < Bs; As < Be; Ae < Bs; No overlap.
	    ## 4) As > Bs; As > Be; Ae > Bs; No overlap.
	    ## Note: As=SeqA_start, Ae=SeqA_end, Bs=SeqB_start and Be=SeqB_end

	    ## To avoid the redundance (row-col, col-row) it will put the
	    ## pairs in a hash ref.

	    my %entries = ();

	    foreach my $id_a (@member_ids) {
		my $as = $post{$id_a}->[0];
		my $ae = $post{$id_a}->[1];
		my @row_values = ();
		foreach my $id_b (@member_ids) {
		    my $bs = $post{$id_b}->[0];
		    my $be = $post{$id_b}->[1];
		    
		    my $pair1 = $id_a . ':' . $id_b;
		    my $pair2 = $id_b . ':' . $id_a;

		    unless (exists $entries{$pair1} && exists $entries{$pair2}){

			my ($nstart, $nend) = (0, 0);
			if ($as <= $bs && $as < $be && $ae > $bs) {
			    $nstart = $bs;
			    $nend = $ae;
			    if ($ae > $be) {
				$nend = $be;
			    }
			}
			elsif ($as >= $bs && $as < $be && $ae > $bs) {
			    $nstart = $as;
			    $nend = $be;
			    if ($ae < $be) {
				$nend = $ae;
			    }
			}

			## Any other posibility will be a non-overlapping. It 
			## will add to the matrix the overlapping regions. 
			## The diagonal always will have start,end and 
			## length = 0.
		    
			if ($id_a ne $id_b) {
			    if ($nstart > 0 && $nend > 0) {
				my %val = ( start  => $nstart, 
					    end    => $nend, 
					    length => $nend-$nstart );
				
				## It will create an aln object with this
				## two sequences to calculate the identity
				## It will get the slide for start and end
				## and also it will remove all the sequences
				## different from $id_a and $id_b
				
				my $seq_a = $align->get_seq_by_id($id_a);
				my $seq_b = $align->get_seq_by_id($id_b);
				my $newaln = Bio::SimpleAlign->new( 
				    -seqs => [$seq_a, $seq_b] );
				my $slcaln = $newaln->slice($nstart, $nend);
		
				my $ident = $slcaln->percentage_identity();
				$val{ident} = $ident;
				
				$matrix->entry($id_a, $id_b, \%val);
				$matrix->entry($id_b, $id_a, \%val);
				print $tfh "$cluster_id\t$id_a\t$id_b\t$val{start}\t$val{end}\t$val{length}\t$val{ident}\n";
			    }
			    else {
				$matrix->entry($id_a, $id_b, $default_vals);
				$matrix->entry($id_b, $id_a, $default_vals);
				print $tfh "$cluster_id\t$id_a\t$id_b\tNO OVLS\n";
			    }
			}
			else {
			    $matrix->entry($id_a, $id_b, $default_vals);
			    $matrix->entry($id_b, $id_a, $default_vals);
			    print $tfh "$cluster_id\t$id_a\t$id_b\tNO OVLS\n";
			}
			$entries{$pair1} = 1;
			$entries{$pair2} = 1;
		    }
		}
	    }
	    $overlaps{$cluster_id} = $matrix;
	}
    }

    return %overlaps;
}


=head2 best_overlaps

  Usage: my %best_overlaps = $phygecluster->best_overlaps();

  Desc: Get the pair of sequences with a longest overlap in an alignment.

  Ret: %hash = ( $cluster_id => [$member_id1, $member_id2] );   

  Args: None.

  Side_Effects: Return overlaps only for clusters with alignments

  Example: my %overlaps = $phygecluster->best_overlaps();
           

=cut

sub best_overlaps {
    my $self = shift;

    my %best_overlaps = ();
    my %overlaps = $self->calculate_overlaps();

    foreach my $cluster_id (keys %overlaps) {

	## Define a hash with key=length and value=pair, It will order the
	## hash and get the longer
	my %ovlength = ();

	my $mtx = $overlaps{$cluster_id};
	my @rownames = $mtx->row_names();
	my @colnames = $mtx->column_names();
	foreach my $row (@rownames) {
	    foreach my $col (@colnames) {
		my $entry = $mtx->get_entry($row, $col);
		$ovlength{$entry->{length}} = [$row, $col];
	    }
	}
	my @ovlength_desc = sort { $b <=> $a } keys %ovlength;
	$best_overlaps{$cluster_id} = $ovlength{$ovlength_desc[0]};
    }
    return %best_overlaps;
}

=head2 best_ovlscore

  Usage: my %best_ovlscore = $phygecluster->best_ovlscore();

  Desc: Get the pair of sequences with a high score based in
        overlap_length * (identity_perc/100)^2

  Ret: %hash = ( $cluster_id => [$member_id1, $member_id2] );   

  Args: None.

  Side_Effects: Return overlaps only for clusters with alignments

  Example: my %ovlscore = $phygecluster->best_overlaps();
           

=cut

sub best_ovlscore {
    my $self = shift;

    my %best_overlaps = ();
    my %overlaps = $self->calculate_overlaps();

    foreach my $cluster_id (keys %overlaps) {

	## Define a hash with key=length and value=pair, It will order the
	## hash and get the longer
	my %ovlength = ();

	my $mtx = $overlaps{$cluster_id};
	my @rownames = $mtx->row_names();
	my @colnames = $mtx->column_names();
	foreach my $row (@rownames) {
	    foreach my $col (@colnames) {
		my $entry = $mtx->get_entry($row, $col);
		my $length = $entry->{length};
		my $ident = $entry->{ident};
		my $ovlscore = $length * ($ident / 100) * ($ident / 100);
		
		$ovlength{$ovlscore} = [$row, $col];
	    }
	}
	my @ovlength_desc = sort { $b <=> $a } keys %ovlength;
	$best_overlaps{$cluster_id} = $ovlength{$ovlength_desc[0]};
    }
    return %best_overlaps;
}



=head2 homologous_search

  Usage: phygecluster->homologous_search();

  Desc: Search homologous sequences to a cluster consensus using 
        Bio::Tools::Run::StandAloneBlast. It will add the best match according
        the highest score by default but different conditions can be used in the
        same way that in the parse_blastfile function.

  Ret: none (load the member in the phygecluster object)

  Args: $args_href, a hash reference with:
        blast   => $array_reference with the same keys that available 
                    arguments in a blast (for example -d <database> -e <evalue>
                    ...). The input sequences will be the cluster consensus 
                    sequence.
        strain  => $strain, for the homologous sequences.
        filter  => $hash_reference with the following permited keys: evalue, 
                   expect, frac_identical, frac_conserved, gaps, hsp_length,
                   num_conserved, num_identical, score, bits, percent_identity
                   and a array reference with condition and value

  Side_Effects: Died if some of the parameters are wrong.
                
  Example:  phygecluster->homologous_search({ blast  => [ -d => $database ],
                                              strain => 'Sly',
                                              filter => { 
                                                           hsp_length => 
                                                                   ['>', 100],
                                                         }, 
                                            })

=cut

sub homologous_search {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None args. were suplied to homologous_search()");

    ## Check the arguments and create the factory object

    my @blast_param = ();
    my $blastdb_file;

    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Arg=$args_href homologous_search() isn't hashref.");
    }
    else {
	unless (defined $args_href->{'blast'}) {
	    croak("ARG. ERROR: No blast arg. was used for search_homologous()");
	}
	else {
	    my $blast_args = $args_href->{'blast'};
	    unless (ref($blast_args) eq 'ARRAY') {
		croak("ARG. ERROR: blast arg.($blast_args) isnt an array ref.");
	    }
	    else {
		@blast_param = @{$blast_args};
		my $enable_db = 0;
		foreach my $param (@blast_param) {
		    if ($param =~ m/^\-d(atabase)?$/) {
			$enable_db = 1;			
		    }
		    elsif ($enable_db == 1) {
			$blastdb_file = $param;
			$enable_db = 0;
		    }
		}
		unless (defined $blastdb_file) {
		    croak("ARG. ERROR: No blast database was used as argument");
		}
	    }
	    if (defined $args_href->{'filter'}) {
		unless (ref($args_href->{'filter'}) eq 'HASH') {
		    croak("ARG. ERROR: filter arg. isn't a hash ref.")
		}
	    }
	}
    }

    ## Define cluster homologous hash

    my %clusters_hmg = ();

    ## Create the tool factory

    my $factory = Bio::Tools::Run::StandAloneBlast->new(@blast_param);
    
    ## Now it will get the consensus sequence from the clusters and run the
    ## blast

    my %clusters = %{$self->get_clusters()};
    my $CL = scalar( keys %clusters);
    my $cl = 0;

    foreach my $cl_id (sort keys %clusters) {
	my $seqfam = $clusters{$cl_id};
	my $align = $seqfam->alignment();

	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($cl, $CL, 
				 "\t\tPerc. of cluster homologous searched:",
				 $cl_id,
		);
	}

	if (defined $align) {

	    ## It will get the consensus sequence stored as consensus_meta
	    ## if not, it will calculate its own consensus using 
	    ## consensus_string function.

	    my $consenseq = ''; 
	    if (defined $align->consensus_meta()) {
		$consenseq = $align->consensus_meta();
	    }
	    else {
		$consenseq = Bio::Seq->new( 
		    -id  => $cl_id,
		    -seq => $align->consensus_string(),
		    );
	    }
	    
	    ## Now it will run the blast per sequence and filter it

	    my $blast_report = $factory->blastall($consenseq);
	    
	    while( my $result = $blast_report->next_result() ) {
		
		my $q_name = $result->query_name();		

		while( my $hit = $result->next_hit() ) {

		    my $s_name = $hit->name();

		    while( my $hsp = $hit->next_hsp() ) {
		    
			## By default it will take the best match, usually
			## the first one.

			unless (defined $args_href->{'filter'}) {
			    unless (defined $clusters_hmg{$cl_id}) {
				$clusters_hmg{$cl_id} = { $s_name => $hsp };
			    }
			}
			else {
			    
			    ## It should use the filter values in the same
			    ## way that in the parse_blastfile function

			    my %filters = %{$args_href->{'filter'}};
			    my $conditions_n = scalar(keys %filters);
			    foreach my $function (keys %filters) {
				
				unless (ref($filters{$function}) eq 'ARRAY') {
				    my $er = "ARG. ERROR: Value used in filter";
				    $er .= " $filters{$function} is not an ";
				    $er .= "array reference";
				    croak($er);
				}
				
				my $cond = $filters{$function}->[0];
				my $val = $filters{$function}->[1];
			    
				unless ($val =~ m/^\d+$/) {
				    my $er3 = "WRONG filtervalues val=";
				    $er3 .= "$function only int. are ";
				    $er3 .= "permited for search_homologous()";
				    croak($er3);
				}
				    
				if ($cond =~ m/^<$/) {
				    if ($hsp->$function < $val) {
					$conditions_n--;
				    }
				} 
				elsif ($cond =~ m/^<=$/) {
				    if ($hsp->$function <= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^==$/) {
				    if ($hsp->$function == $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>=$/) {
				    if ($hsp->$function >= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>$/) {
				    if ($hsp->$function > $val) {
					$conditions_n--;
				    }
				}
				else {
				    my $er4 = "WRONG filtervalues val=";
				    $er4 .= "$function, it is not a ";
				    $er4 .= "permited condition ('<','<=',";
				    $er4 .= "'==','>=' or '>')\n";
				    croak($er4);
				}
			    }    
			    
			    ## It will add a new relation only if all the
			    ## conditions have been satisfied
			    if ($conditions_n == 0) {
				unless (exists $clusters_hmg{$cl_id}) {
				    $clusters_hmg{$cl_id} = {$s_name => $hsp};
				}
				else {
				    my %members = %{$clusters_hmg{$cl_id}};
				    unless (defined $members{$s_name}) {
					$clusters_hmg{$cl_id}->{$s_name} = $hsp;
				    }
				}
			    }
			}
		    }
		}
	    }
	}
    }

    ## Now all the relations should be contained in the cluster_hmlg hash.
    ## so now it will load them into the family objects. Before do that, it will
    ## get all the sequences from the database file to load them as seq objects.

    my %blastseqs = parse_seqfile({ sequencefile => $blastdb_file });
    my $strain_href = $self->get_strains();

    foreach my $cl_id2 (keys %clusters) {
	my $seqfam2 = $clusters{$cl_id2};
	my $align2 = $seqfam2->alignment();

	my $consenseq = ''; 
	if (defined $align2->consensus_meta()) {
	    $consenseq = $align2->consensus_meta();
	}
	else {
	    $consenseq = Bio::Seq->new( 
		-id  => $cl_id2,
		-seq => $align2->consensus_string(),
		);
	}
	
	if (defined $clusters_hmg{$cl_id2}) {
	    my @newmemb = keys %{$clusters_hmg{$cl_id2}};
	    foreach my $memb_id (@newmemb) {
		
		## Add a new sequence to the cluster

		my $seq = $blastseqs{$memb_id};
		$seqfam2->add_members([$seq]);

		## Get the data from the blast to add a new seq in the align.

		my $hsp2 = $clusters_hmg{$cl_id2}->{$memb_id};
		my $hit_str = $hsp2->hit_string();
		my $query_str = $hsp2->query_string();
		my $qst_blast = $hsp2->start('query');
		my $qen_blast = $hsp2->end('query');
		my $hst_blast = $hsp2->start('hit');
		my $hen_blast = $hsp2->end('hit');
		my $qlen_blast = $hsp2->length('query');
		my $hlen_blast = $hsp2->length('hit');
		my $orig_query_en = $consenseq->length();
		my $cons_string = $consenseq->seq();

		## The sequence that it needs to add to the alignment
		##
		## qqqqqqqqqq1===============2qqqqqqqqqq     query
		##     hhhhhh3===============4hhhhhhhhhhhhh  hit
		##
		## Where query is the consensus for the original align.
                ## 1) Get hit for 3 to 4 (using hit_string function it get the
	        ##    string trimmed)
                
		my $trimseq = '';
		if ($hst_blast > $hen_blast) {
		    my @subseq = split(//, $hit_str);
		    $trimseq = join('', reverse(@subseq));
		}
		else {
		    $trimseq = $hit_str;		    
		}
		
		## Count how many gaps has the sequence to set the right end
		my $trimseqnogaps = $trimseq;
		$trimseqnogaps =~ s/[-|\*|_]//g;
		my $nogapslength = length($trimseqnogaps);

		## 2) Create a gap seq as long as 'q' pre 1

		my $seq_down = '';
		while ($qst_blast > 1) {
		    $seq_down .= '-';
		    $qst_blast--; 
		}

		## 3) Create a gap seq as long as 'q' post 2

		my $seq_up = '';
		my $curr_length = length($seq_down .  $trimseq);
		while ($curr_length < $orig_query_en) {
		    $seq_up .= '-';
		    $curr_length++; 
		}
		
		## 4) Build the seq as $seq_up + $trimseq + $downseq
		my $alignseq = $seq_down . $trimseq . $seq_up;

		my $locseq = Bio::LocatableSeq->new( 
		    -seq   => $alignseq,
		    -id    => $memb_id,
		    -start => $hsp2->start('query'),
		    -end   => $hsp2->start('query') + $nogapslength - 1,
		    );

		my $align2 = $seqfam2->alignment();
		my $alignlength = $align2->length();
		
		$align2->add_seq( -SEQ => $locseq, -ORDER => 1);

		## Also it will add a strain if is defined strain argument

		if (defined $args_href->{'strain'}) {
		    $strain_href->{$memb_id} = $args_href->{'strain'};
		}
	    }
	}
    }
}


=head2 reroot_trees

  Usage: $phygecluster->reroot_trees($args_href);

  Desc: Reroot the trees of the phygecluster object

  Ret: None.

  Args: A hash reference with the following options:
        midpoint   => 1,
        strainref  => $strainname,
        longestref => 1,

  Side_Effects: Die if hash argument is wrong or if more than one is used.
                A tag 'reroot_as_' + argument is added to the tree.
                Skip the trees without strains detailed in the option.

  Example: $phygecluster->reroot_trees($args_href);
           

=cut

sub reroot_trees {
    my $self = shift;
    my $arg_href = shift ||
	croak("ARG. ERROR: No argument was supplied to reroot_trees().");

    ## Check arguments.

    unless (ref($arg_href) eq 'HASH') {
	croak("ARG. ERROR: $arg_href supplied to reroot_trees is not HASHREF");
    }
    else {
	my %perm_args = ( midpoint   => 1, 
			  strainref  => '\w+', 
			  longestref => 1,
	    );
	foreach my $argname (keys %{$arg_href}) {
	    unless (exists $perm_args{$argname}) {
		croak("ARG. ERROR: $argname isnt valid arg for reroot_trees()");
	    }
	    else {
		my $val = $arg_href->{$argname};
		my $permval = $perm_args{$argname};
		unless ($val =~ m/$permval/) {
		    croak("ARG. ERROR: $val value isnt valid for reroot_trees");
		}
	    }
	}
	if (scalar(keys %{$arg_href}) > 1) {
	    croak("ARG. ERROR: Only one argument can be used for reroot_trees");
	}
    }


    ## Create a hash to store the failed rooting seqfams

    my %failed = ();


    ## Get trees, raw sequences and strains

    my %seqfams = %{$self->get_clusters()};
    my $CL = scalar( keys %seqfams );
    my $cl = 0;

    my %strains = %{$self->get_strains()};

    foreach my $cluster_id (keys %seqfams) {
	my $tree = $seqfams{$cluster_id}->tree();

	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($cl, $CL, "\t\tPerc. of trees rerooted:",
				 $cluster_id,
		);
	}


	if (defined $tree) {
	    
	    if (exists $arg_href->{midpoint}) {

		## It will reset the root into the object
		my $midpoint_node = _set_midpoint_root($tree);

		unless (defined $midpoint_node) {
		    $failed{$cluster_id} = $seqfams{$cluster_id};
		}
	    }
	    elsif (exists $arg_href->{strainref}) {
		my $str_ref = $arg_href->{strainref};
		
		## 0) Define the strain nodes

		my @str_nodes = ();

		## 1) Get all the sequences_id for this tree, check the strain
		##    and add to the hash
		
		my @leaves = $tree->get_leaf_nodes();
		foreach my $lnode (@leaves) {
		    my $lnode_id = $lnode->id();
		    
		    if (exists $strains{$lnode_id}) {
			if ($strains{$lnode_id} eq $str_ref) {
			    push @str_nodes, $lnode;
			}
		    }
		}

		## 2) Two options, if there are more than one node, it
		##    will select the node with the longest distance to
		##    the common ancestor. If there are only one, it will 
		##    use that.

		my $newroot;
		if (scalar(@str_nodes) > 1) {
		    
		    ## Get the common ancestor
		    my $common_ancestor;
		    my @nodes = $tree->get_nodes();
		    foreach my $node (@nodes) {
			my $ances = $node->ancestor();
			unless (defined $ances) {
			    $common_ancestor = $node;
			}
		    }

		    ## Calculate distances between common ancestor and strnodes
		    ## and define the longest. After that get the root

		    if (defined $common_ancestor) {
			my $longestdist = 0;
			foreach my $str_node (@str_nodes) {
			    my $dist = $tree->distance( 
				[$common_ancestor, $str_node] );
			    if ($dist >= $longestdist) {
				$longestdist = $dist;
				$newroot = $str_node;
			    }
			}
		    }

		}
		elsif (scalar(@str_nodes) == 1) {
		    $newroot = $str_nodes[0];
		}

		if (defined $newroot) {
		    $tree->reroot($newroot, 0);
		}
		else {
		    $failed{$cluster_id} = $seqfams{$cluster_id};
		}

	    }
	    elsif (exists $arg_href->{longestref}) {
		
		## First get the seq_ids and the lenghts 
		
		my %seql = ();
		my @seqs = $seqfams{$cluster_id}->get_members();
		foreach my $seq (@seqs) {
		    $seql{$seq->id()} = $seq->length();
		}

		## Second get the nodes ids and the max seqlenght
		
		my $longest_node;
		my $longest_length = 0;
		my @leaves = $tree->get_leaf_nodes();
		foreach my $lnode (@leaves) {
		    my $lnode_id = $lnode->id();
		    
		    if (exists $seql{$lnode_id}) {
			if ($seql{$lnode_id} >= $longest_length) {
			    $longest_node = $lnode;
			    $longest_length = $seql{$lnode_id};
			}
		    }
		}

		## Third set the root

		if (defined $longest_node) {
		    $tree->reroot($longest_node, 0);
		}
		else {
		    $failed{$cluster_id} = $seqfams{$cluster_id};
		}
	    }	    
	}
    }
    return %failed;
}

=head2 _set_midpoint_root

  Usage: $midpoint_node = _set_midpoint_root($tree);

  Desc: Calculate the midpoint node for a tree (Bio::Tree::TreeFunctionsI 
        calculate the midpoint for a node but not for the complete tree)

  Ret: Midpoint node (a Bio::Tree::Node object).

  Args: A tree object (Bio::Tree::Tree)

  Side_Effects: Die if no tree object is supplied.
                Return undef if iot can not set the midpoint as a root

  Example: $midpoint_node = _set_midpoint_root($tree);
           

=cut

sub _set_midpoint_root {
    my $tree = shift ||
	croak("ERROR: No tree argument was used for _set_midpoint_root()");

    unless (ref($tree) eq "Bio::Tree::Tree") {
	croak("ERROR: $tree isnt a Bio::Tree::Tree obj for _set_midpoint_root");
    }

    ## First get all the lineages distances for all the leaves

    my %distances = ();
    my %nodespair = ();
    my @leaves = $tree->get_leaf_nodes();
    foreach my $lnode1 (@leaves) {
	my $lnode_id1 = $lnode1->id();

	foreach my $lnode2 (@leaves) {
	    my $lnode_id2 = $lnode2->id();

	    ## Get the distance only if they are different

	    if ($lnode_id1 ne $lnode_id2) {
		
		my $distance = $tree->distance([$lnode1, $lnode2]);
		## create an array with the names and sort before use as keys
		my $idpair = join('-', sort ($lnode_id1, $lnode_id2) );

		unless (exists $distances{$idpair}) {
		    $distances{$idpair} = $distance;
		    $nodespair{$idpair} = [$lnode1, $lnode2];
		}
	    }
	}
    }

    ## Now it will order by branch length (from longer to shorter)

    my @farnodes = sort {$distances{$b} <=> $distances{$a}} keys %distances;

    ## Take the two longest lineages

    my $test = join(',', @farnodes);

    my $farpair_aref = $nodespair{$farnodes[0]}; 

    ## It will calculate the middle point

    my $midbranch = $distances{$farnodes[0]} / 2;

    ## Get the nodes between this two leaves, to do that it will take
    ## all the ancestors from this leaves to the top.
    
    my $low_com_anc = $tree->get_lca(@{$farpair_aref});

    my @ancestors1 = ($farpair_aref->[0]);
    my $lineancestor1 = $farpair_aref->[0]->ancestor();
    if (defined $lineancestor1 && $lineancestor1 ne $low_com_anc) {
	push @ancestors1, $lineancestor1;
	while ($lineancestor1 ne $low_com_anc) {
	    $lineancestor1 = $lineancestor1->ancestor();
	    push @ancestors1, $lineancestor1;
	}
    }

    my @ancestors2 = ($farpair_aref->[1]);
    my $lineancestor2 = $farpair_aref->[1]->ancestor();
    if (defined $lineancestor2 && $lineancestor2 ne $low_com_anc) {
	push @ancestors2, $lineancestor2;
	while ($lineancestor2 ne $low_com_anc) {
		$lineancestor2 = $lineancestor2->ancestor();
		push @ancestors2, $lineancestor2;
	}
    }

    ## Join both arrays (using reverse for the second ton put for far to close)
    my @betw_nodes = (@ancestors1, reverse(@ancestors2));

    ## Now it will get sustract each ancestor distance for each lineage

    my $new_node_branch = '';
    my $ancestor;
    foreach my $bet_node (@betw_nodes) {
       
	my $linbranch = $bet_node->branch_length();
	
	if (defined $linbranch) {
	    if ($midbranch > $linbranch) {
		$midbranch -= $linbranch;
	    }
	    else {
		unless (defined $ancestor) {
		    my $linpart1 = $linbranch - $midbranch;
		    $new_node_branch = $linbranch - $linpart1;
		    $ancestor = $bet_node;
		}
	    }
	}
    }

    ## Finally it will create a node in the ancestor node with this length

    my $newnode;
    if (defined $ancestor) {
	$newnode = $ancestor->create_node_on_branch( 
	    -POSITION => $new_node_branch, 
	    -FORCE => 1,
	    );	
	$tree->reroot($newnode);
    }
    return $newnode;
}

=head2 _get_outgroup_id

  Usage: $member_id = _get_outgroup_id({ seqfam    => $seqfam, 
                                      strains   => \%strains, 
                                      reference => $reference,
                                      alignprog => $name,
                                      alignargs => \@args,
                                      });

  Desc: Return the member_id based in the reference for a group of sequences 
        in a seqfam object.
        If there are more than one option (it will compare these sequences with
        the rest of them with Smith-Waterman (SW) algorithm picking the 
        sequence with the lower score.

  Ret: $member_id, a sequence id

  Args: A hash reference with the following elements:
        seqfam    => a Bio::Cluster::SequenceFamily object
        strains   => a hash reference with key=seq_id and value=strain
        reference => a scalar with the strain reference name
        alignprog => alignment program name (clustalw by default)
        alignargs => alignment arguments

  Side_Effects: Die if none of the requested arguments are supplied

  Example: $member_id = _get_outgroup_id({ 
                              seqfam    => $seqfam, 
                              strains   => { 'seq1' => 'str1', seq2' => 'str2'},
                              reference => 'str2' });
           

=cut

sub _get_outgroup_id {
    my $argshref = shift ||
	croak("ERROR: No argument href was used for _get_outgroup_id()");

    ## Checkings

    unless (ref($argshref) eq "HASH") {
	croak("ERROR: $argshref isnt a HASH REF. for _get_outgroup_id");
    }
    
    my $seqfam = $argshref->{seqfam} ||
	croak("No Bio::Cluster::SequenceFamily was supplied _get_outgroup_id");

    unless (ref($seqfam) eq 'Bio::Cluster::SequenceFamily') {
	croak("$seqfam isnt a Bio::Cluster::SequenceFamily at get_outgroup_id");
    }

    my $strainshref = $argshref->{strains} ||
	croak("No strains hash ref. was supplied _get_outgroup_id");

    my %strains;
    unless (ref($strainshref) eq 'HASH') {
	croak("$strainshref isnt a HASH REF. at get_outgroup_id");
    }
    else {
	%strains = %{$strainshref};
    }

    my $ref = $argshref->{reference} ||
	croak("No (outgroup) reference was supplied _get_outgroup_id");

    my %perm_prog = (
	clustalw => 'Bio::Tools::Run::Alignment::Clustalw',
	kalign   => 'Bio::Tools::Run::Alignment::Kalign',
	mafft    => 'Bio::Tools::Run::Alignment::MAFFT',
	muscle   => 'Bio::Tools::Run::Alignment::Muscle',
	tcoffee  => 'Bio::Tools::Run::Alignment::TCoffee',
	);

    ## Check the programs and create the alignfactory
    
    if (exists $argshref->{alignprog}) {
	my $pprog = join(',', sort(keys %perm_prog));
	unless (exists $perm_prog{$argshref->{alignprog}}) {
	    my $er1 = "Program selected for _get_outgroup_id()";
	    $er1 .= "isnt in the list of permited programs ($pprog)";
	    croak($er1);
	}
    }
    else {
	$argshref->{alignprog} = 'clustalw';
	$argshref->{alignargs} = [ quiet => 1 ];
    }
    my $alignmodule = $perm_prog{$argshref->{alignprog}};

    my @alignargs = ();
    if (exists $argshref->{alignargs}) {
	unless (ref($argshref->{alignargs}) eq 'ARRAY') {
	    my $er4 = "'alignargs' args. supplied to _get_outgroup_id()";
	    $er4 .= "doesn't contains 'alignargs' specification";
	    croak($er4);
	}
	else {
	    @alignargs = @{$argshref->{alignargs}};
	}
    }
 
    ## Define the storage variables

    my $ref_id;
    my @candidates;
    my @non_candidates;

    ## Select the candidates sequences where strain = reference

    my @seqs = $seqfam->get_members();
    foreach my $seq (@seqs) {
	my $seqid = $seq->id();
	my $str = $strains{$seqid};
	if (defined $str) {
	    if ($str eq $ref) {
		push @candidates, $seq;
	    }
	    else {
		push @non_candidates, $seq;
	    }
	}
    }

    ## Count how many candidates there are. For more than one it will align
    ## other members with non-candidates seqs, choosing the candidate with
    ## the lower score.

    if (scalar(@candidates) > 1) {
	
	## it will complare the sequences using Smith-Waterman algorithm 
	my $factory = $alignmodule->new(@alignargs);

	## Lower score (sequences more different between them)
	my $low_score;
	
	foreach my $cand (@candidates) {
	    foreach my $non_cand (@non_candidates) {
		my $aln = $factory->align([$cand,$non_cand]);
		my $stats = Bio::Align::PairwiseStatistics->new();
		my $score = $stats->score_nuc($aln);
		
		unless (defined $low_score) {
		    $low_score = $score;
		    $ref_id = $cand->id();
		}
		else {
		    if ($low_score >= $score) {
			$low_score = $score;
			$ref_id = $cand->id();
		    }
		}
	    }
	}
    }
    elsif (scalar(@candidates) == 1) {
	$ref_id = $candidates[0]->id();
    }
    
    return $ref_id;
}



################################
## PROGRAMS RUNNING FUNCTIONS ##
################################


=head2 run_alignments

  Usage: my @failed = phygecluster->run_alignments({ program => $prog, 
                                             parameters => $parameters_href});

  Desc: Create the sequence aligns for each cluster and load it into the
        Bio::Cluster::SequenceFamily object

  Ret: @failed, an array with the cluster_id of the failed alignments.
       (load the alignments into the Bio::Cluster::SequenceFamily object)

  Args: $args_href, a hash reference with the following permited keys:
        program => $scalar, parameters => $array_ref with program parameters

  Side_Effects: Died if some of the parameters are wrong.
                It does not run alignments over singlets (cluster with 1 member)

  Example:  phygecluster->run_alignments({ program    => $prog, 
                                           parameters => $parameters_href});

=cut

sub run_alignments {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None args. were suplied to run_alignments()");

    ## Check the arguments and create the factory object

    my $factory;
    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Arg=$args_href for run_alignments() isn't hashref.");
    }
    else {
	my %args = %{$args_href};
	
	unless (exists $args{program}) {
	    my $er0 = "ARG. ERROR: Args. supplied to run_alignments doesn't ";
	    $er0 .= "contains 'program' specification";
	    croak($er0);
	}
	else {
	    my %perm_prog = (
		clustalw => 'Bio::Tools::Run::Alignment::Clustalw',
		kalign   => 'Bio::Tools::Run::Alignment::Kalign',
		mafft    => 'Bio::Tools::Run::Alignment::MAFFT',
		muscle   => 'Bio::Tools::Run::Alignment::Muscle',
		tcoffee  => 'Bio::Tools::Run::Alignment::TCoffee',
		);

	    my %perm_progargs = (
		clustalw => [ 
		    @Bio::Tools::Run::Alignment::Clustalw::CLUSTALW_PARAMS,
		    @Bio::Tools::Run::Alignment::Clustalw::CLUSTALW_SWITCHES,
		    @Bio::Tools::Run::Alignment::Clustalw::OTHER_SWITCHES,
		],
		kalign   => [
		    @Bio::Tools::Run::Alignment::Kalign::KALIGN_PARAMS,
		    @Bio::Tools::Run::Alignment::Kalign::KALIGN_SWITCHES,
		],
		mafft    => [ 
		    @Bio::Tools::Run::Alignment::MAFFT::MAFFT_PARAMS,
		    @Bio::Tools::Run::Alignment::MAFFT::MAFFT_SWITCHES,
		    @Bio::Tools::Run::Alignment::MAFFT::OTHER_SWITCHES,
		],
		muscle   => [
		    @Bio::Tools::Run::Alignment::Muscle::MUSCLE_PARAMS,
		    @Bio::Tools::Run::Alignment::Muscle::MUSCLE_SWITCHES,
		],
		tcoffee  => [
		    @Bio::Tools::Run::Alignment::TCoffee::TCOFFEE_PARAMS,
		    @Bio::Tools::Run::Alignment::TCoffee::TCOFFEE_SWITCHES,
		    @Bio::Tools::Run::Alignment::TCoffee::OTHER_SWITCHES,
		],
		);

	    

	    ## Define the permited params and switches that will be 
	    ## extracted from the program module

	    my %perm_progparam = ();

	    ## Check the program

	    my $pprog = join(',', sort(keys %perm_prog));
	    unless (exists $perm_prog{$args{program}}) {
		my $er1 = "ARG. ERROR: program selected for run_alignments()";
		$er1 .= "is not in the list of permited programs ($pprog)";
		croak($er1);
	    }
	    else {
		## Get the parameters and the switches for that program
		## And check if they are right
		## Change to lowercase everything
		
	        foreach my $pr_param ( @{$perm_progargs{$args{program}}} ) {
		    $perm_progparam{lc($pr_param)} = 1;
		}		
	    }

	    unless (exists $args{parameters}) {
		my $er3 = "ARG. ERROR: Args. supplied to run_alignments ";
		$er3 .= "doesn't contains 'parameters' specification";
		croak($er3);
	    }
	    else {
		unless (ref($args{parameters}) eq 'HASH') {
		    my $er4 = "ARG. ERROR: 'parameters' args. supplied to ";
		    $er4 .= "run_alignments()";
		    $er4 .= "doesn't contains 'parameters' specification";
		    croak($er4);
		}
		else {

		    $factory = $perm_prog{$args{program}}->new();

		    foreach my $par ( keys %{$args{parameters}} ) {
			unless (exists $perm_progparam{lc($par)}) {
			    my $er5 = "ERROR: $par is not a valid ";
			    $er5 .= "parameter/switch for $args{program}.\n";
			    my $valid = join("\n", keys %perm_progparam);
			    $er5 .= "$valid\n\n";
			    croak($er5);
			}
			else {
			    my $val = $args{parameters}->{$par};
			    my $program_param = lc($par);
			    if (defined $val && length($val) > 0) {
				$factory->$program_param($val);
			    }
			    else {
				$factory->$program_param(1);
			    }
			}
		    }
		}
	    }
	}	    
    }

    my @failed = ();

    if (defined $factory) {
 
	my %clusters = %{$self->get_clusters()};

	my $a = 0;
	my $t = scalar(keys %clusters);

	foreach my $cluster_id (sort keys %clusters) {
	 
	    $a++;

	    my @seq_members = $clusters{$cluster_id}->get_members();

	    ## Only make sense if the cluster has more than one member
	    
	    my $test = scalar(@seq_members);

	    if (scalar(@seq_members) > 1) {

		## Some tools trim the sequence id, so it is better to replace
		## them for some index and rereplace after run the alignment

		my %seqids = ();
		my $i = 1;
		foreach my $seq (@seq_members) {
		    my $id = $seq->display_id();
		    $seqids{$i} = $id;
		    $seq->display_id($i);
		    $i++;
		}
		
		if ($self->is_on_reportstatus) {
		    print_parsing_status($a, $t, 
					 "\t\tPerc. of alignments produced:",
					 $cluster_id,
			);
		}


		my $alignobj = $factory->align(\@seq_members);

		## Come back to old ids. It require to change the name
		## in the object and reset the sequence object in the alignment
		## object with the new names... to let the object get all the
		## variables that it need it

		## Remove members from Bio::Cluster::SequenceFamily to add
		## the seqs with the right id (align creates a new seq objects) 

		if (defined $alignobj) {
		    $clusters{$cluster_id}->remove_members();
		    foreach my $seq2 (@seq_members) {
			$seq2->display_id($seqids{$seq2->display_id()});
			$clusters{$cluster_id}->add_members([$seq2]);
		    }
		    
		    foreach my $seqobj ($alignobj->each_seq()) {
			my $index = $seqobj->display_id();
			$alignobj->remove_seq($seqobj);
			$seqobj->display_id($seqids{$index});
			$alignobj->add_seq($seqobj);
			
		    }

		    ## Also it will set the alinments into the SequenceFamily 
		    ## object
		

		    $clusters{$cluster_id}->alignment($alignobj);
		}
		else {
		    push @failed, $cluster_id;
		}
	    }
	}
    }
    return @failed;
}

=head2 run_distances

  Usage: my @failed = $phygecluster->run_distances($method);

  Desc: Calculates a distance matrix for all pairwise distances of
        sequences in an alignment using Bio::Align::DNAStatistics object

  Ret: @failed, an array with the failed cluster_id
       (it loads %distances, a hash with keys=cluster_id and 
       value=Bio::Matrix::PhylipDis object into the phyGeCluster object)

  Args: A hash reference with following keys:
        method, a scalar to pass to the Bio::Align::DNAStatistics->distance()
                  function (JukesCantor,Uncorrected,F81,Kimura,Tamura or 
                  TajimaNei).
        quiet, with values 1 or 0

  Side_Effects: Died if the methos used is not in the list of available
                method for Bio::Align::DNAStatistics object.
                It not return keys for the clusters that do not have alignment
                or for JukesCantor or F81 methods when gaps >= alignment length.
                It will run JukesCantor distance by default.

  Example: $phygecluster->run_distances({method => 'Kimura'});

=cut

sub run_distances {
    my $self = shift;
    my $arghref = shift;
    
    my $method = '';
    my $quiet = 0;
    if (defined $arghref) {
	unless (ref($arghref) eq 'HASH') {
	    croak("ERROR: Arg. supplied to run_distances is not a hash ref.")
	}
	$method = $arghref->{'method'} || 'JukesCantor';
	$quiet = $arghref->{'quiet'} || 0;
	unless ($quiet =~ m/^[1|0]$/) {
	    croak("ERROR: quiet only can take 0 or 1 values");
	}
    }
    
    ## Create the Bio::Align::DNAStatistics object

    my $align_stats = Bio::Align::DNAStatistics->new();

    ## Define if the method is a valid method

    my %avmethods = ();
    my @available_methods = $align_stats->available_distance_methods();

    foreach my $av_method (@available_methods) {
	$avmethods{$av_method} = 1;
    }
    
    unless (defined $avmethods{$method}) {
	my $error_message = "ERROR METHOD: $method is not an available for ";
	$error_message .= "run_distance() method.";
	$error_message .= "\nAvailable distance methods:\n\t"; 
	$error_message .= join("\n\t", @available_methods) . "\n";
	croak($error_message);
    }


    my %dist = ();

    my %failing_gapmethod = ( 
	'JukesCantor' => 1,
	'F81'         => 1, 
	);

    ## Get the alignment objects

    my %clusters = %{$self->get_clusters()};

    my $t = scalar( keys %clusters);
    my $a = 0;
    
    my @failed = ();

    foreach my $cluster_id (sort keys %clusters) {

	my $alignobj = $clusters{$cluster_id}->alignment();
	my @members = $clusters{$cluster_id}->get_members();
	foreach my $member (@members) {
	    my $memb_id = $member->id();
	}

	$a++;

	if (defined $alignobj) {
	   
	    
	    ## Some alignments can have a problem because there are non-ATGC
	    ## nt that produce can produce gaps in the alignment and the number
	    ## of those gaps are bigger than the sequence length. For those
	    ## cases Bio::Align::DNAStatistics could crash for some distance
	    ## methods. As easy solution it will skip the methods where 
	    ## gaps >= distance can give problems

	    my $length = $alignobj->length();
	    my $gaps = 0;
	    my @gapchars = ('.', '-');
	    my $gaptype = '-';  ## Dash by default

	    ## Count gaps

	    foreach my $seqobj ( $alignobj->each_seq() ) {
		my @seq = split(//, $seqobj->seq());
		foreach my $nt (@seq) {
		    foreach my $gapelem (@gapchars) {
			if ($nt eq $gapelem) {
			    $gaps++;
			    $gaptype = $gapelem;
			}
		    }
		}
	    }

	    my $skip_distance = 0;

	    ## Apply the filter for the failing distance methods

	    if (defined ($failing_gapmethod{$method})) {
		if ($gaps >= $length) {
		    $skip_distance = 1;
		}
	    }

	    if ($self->is_on_reportstatus) {
		print_parsing_status($a, $t, 
				     "\t\tPerc. of distances calculated:",
				     $cluster_id,
		    );
	    }


	    if ($skip_distance == 0) {

		## Some tools trim the sequence id, so it is better to replace
		## them for some index and rereplace after run the alignment

		my %seqids = ();
		my $i = 1;
		foreach my $seqobj ($alignobj->each_seq()) {
		    $seqids{$i} = $seqobj->display_id();
		    $alignobj->remove_seq($seqobj);
		    $seqobj->display_id($i);
		    $alignobj->add_seq($seqobj);
		    $i++;
		}

		my $distmatrix;
		try {
		    if ($quiet == 1) {
			local $SIG{__WARN__} = sub {};
			$distmatrix = $align_stats->distance( 
			    -align  => $alignobj,
			    -method => $method,
			    );
		    }
		    else {
			$distmatrix = $align_stats->distance( 
			    -align  => $alignobj,
			    -method => $method,
			    );
		    }
		}
		finally {

		    ## After run distance (independently if it success or not)
		    ## it needs to change the seq from the aligns		

		    foreach my $seqobj2 ($alignobj->each_seq()) {
			my $id2 = $seqobj2->display_id();
			$alignobj->remove_seq($seqobj2);
			$seqobj2->display_id($seqids{$id2});
			$alignobj->add_seq($seqobj2);
		    }

		    if (@_) {
			unless ($quiet == 0) {
			    print STDERR "ERROR for run_distances.\n@_\n";
			    push @failed, $cluster_id;
			}
		    }
		    else {

			## Before set the matrix it will replace the 
			## matrix headers, in names and in the matrix too
			
			if (defined $distmatrix) {

			    my @oldnames = ();

			    foreach my $name (@{$distmatrix->names()}) {
				push @oldnames, $seqids{$name};

				my $vals_href = $distmatrix->_matrix()->{$name};
				foreach my $key2 (keys %{$vals_href}) {
				    $vals_href->{$seqids{$key2}} = 
					delete($vals_href->{$key2});
				}
				
				$distmatrix->_matrix()->{$seqids{$name}} =
				    delete($distmatrix->_matrix()->{$name});
			    }
			    $distmatrix->names(\@oldnames);

			    $dist{$cluster_id} = $distmatrix;
			}
		    }
		};		
	    }	    
	}
    }
    $self->set_distances(\%dist);
    return @failed;
}


=head2 run_bootstrapping

  Usage: $phygecluster->run_bootstrapping($args_href);

  Desc: Calculates the bootstrapping for a phygecluster object. It stores
        the bootstrapping alignments into the object, as a hash, key=cluster_id
        and value=array reference of alignments. It use PhyGeBoots object.

  Ret: none (it loads %bootstrap as keys=cluster_id and value=consensus object)

  Args: $args_href, a hash reference with the following options:
         + run_bootstrap => a hash ref. with args. (datatype, permute, 
                            blocksize, replicates, readweights, readcat & quiet)
         + run_distances => a hash ref. with args. (method => (JukesCantor,
                            Uncorrected,F81,Kimura,Tamura or TajimaNei))
         + run_njtrees   => a hash ref. with args. (type => NJ|UPGMA, 
                            outgroup => int, lowtri => 1|0, uptri => 1|0,
                            subrep => 1|0 or/and jumble => int)
         + run_mltrees   => a hash ref. with args. (phyml_arg => {}, $hash ref 
                            with phyml arguments               
         + run_consensus => a hash ref. with args. (type => '\w+', rooted => 
                            '\d+', outgroup => '\d+', quiet => '[1|0]',)

        (for more information: 
         http://evolution.genetics.washington.edu/phylip/doc/seqboot.html
         http://www.atgc-montpellier.fr/phyml/usersguide.php )

  Side_Effects: Died if the arguments are wrong.
                Skip the clusters that do not have any alignment
                

  Example: $phygecluster->run_bootstrapping(
                        { 
                          run_bootstrap => { 
                             datatype   => 'Sequence',
                             replicates => 1000,
                             quiet      => 1,
                          },
                          run_distances => {
                             method => 'Kimura',
                          },
                          run_njtrees   => {
                             type  => 'NJ',
                             quiet => 1,
                          },
                          run_consensus => {
                             quiet => 1,
                          }
                        }
			);

=cut

sub run_bootstrapping {
    my $self = shift;
    my $args_href = shift;
    
    ## Bootstrap tool uses the arguments as a array, so the argument checking
    ## also will change them to this format

    my %default_args = (
	replace_no_atcg => 0,
	report_status => 0,
	run_bootstrap => { 
	    datatype   => 'Sequence',
	    replicates => 1000,
	    quiet      => 1,
	},
	run_distances => {
	    method => 'JukesCantor',
	},
	run_njtrees   => {
	    type => 'NJ',
	    quiet => 1,
	},
	run_mltrees   => {
	},
	run_consensus => {
	    quiet => 1,
	},
	);

    ## Checking args.  

    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    my $err = "ARG. ERROR: Arg. supplied to run_bootstrapping() arent ";
	    $err .= "an hashref";
	    croak($err);
	}
	else {
	    foreach my $argkey (keys %{$args_href}) {
		my $val = $args_href->{$argkey};
		unless ($argkey =~ m/(replace_no_atcg|report_status)/) {
		    unless (exists $default_args{$argkey}) {
			my $err = "ARG. ERROR: $argkey is not a permited arg. ";
			$err .= "for run_bootstrapping() function";
			croak($err);
		    }
		    unless (ref($val) eq 'HASH') {
			my $err = "ARG. ERROR: $val for $argkey argument isnt ";
			$err .= "an hash ref for run_bootstrapping() function";
			croak($err);
		    }
		}
	    }
	}
    }
    else {
	## Remove the default redundancy (run_mltree)
	delete($default_args{run_mltree});
	$args_href = \%default_args;
    }

    ## Now it will run all the bootstrapping process for each cluster
    ## Define the hash to store the alignments

    my %bootstr = ();

    my %clusters = %{$self->get_clusters()};
    my $strains_href = $self->get_strains();

    my $a = 0;
    my $t = scalar( keys %clusters );

    foreach my $cluster_id (sort keys %clusters) {
	$a++;
	my $seqfam = $clusters{$cluster_id};
	my $align = $seqfam->alignment();
	
	## Make sense run the bootstrapping only for clusters with alignments
	if (defined $align) {
	    my %args = %{$args_href};
	    $args{seqfam} = $seqfam;
	    $args{strains} = $strains_href;
	    my $memb_n = $align->num_sequences();

	    if ($self->is_on_reportstatus) {
		print_parsing_status($a, $t, 
				     "\t\tPerc. of bootstrapping calculated:",
				     $cluster_id,
		    );
	    }

	    my $phygeboots = PhyGeBoots->new(\%args);
	    my $consensus = $phygeboots->get_consensus();
	    my $trees_n = scalar( $phygeboots->get_trees());

	    if (defined $consensus && ref($consensus) =~ m/Bio::Tree/) {
		$bootstr{$cluster_id} = $consensus;
	    }
	}
    }
    
    ## Finally it will load the data into the object

    $self->set_bootstrapping(\%bootstr);
}

=head2 run_njtrees

  Usage: $phygecluster->run_njtrees($arg_href);

  Desc: Calculates every tree for the distances contained into the SeqGeCluster
        object and load it into Bio::Cluster::SequenceFamily object

  Ret: None (it loads the tree into Bio::Cluster::SequenceFamily object)

  Args: $args_href, a hash reference with the following options:
        type            => NJ|UPGMA, 
        outgroup        => int, 
        lowtri          => 1|0, 
        uptri           => 1|0, 
        subrep          => 1|0,
        jumble          => int, 
        quiet           => 1|0,
        outgroup_strain => $strain_name
        (for more information: 
         http://evolution.genetics.washington.edu/phylip/doc/seqboot.html)
 

  Side_Effects: Died if the arguments are wrong.
                
  Example: $phygecluster->run_njtrees($arg_href);

=cut

sub run_njtrees {
    my $self = shift;
    my $args_href = shift;

    my %perm_args = ( type            => '(NJ|UPGMA)', 
		      outgroup        => '\d+', 
		      lowtri          => '[1|0]', 
		      uptri           => '[1|0]', 
		      subrep          => '[1|0]', 
		      jumble          => '\d+', 
		      quiet           => '[1|0]',
		      outgroup_strain => '\w+', 
	);

    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ARG. ERROR: Arg. supplied to run_njtrees() arent hashref");
	}

	foreach my $arg (keys %{$args_href}) {
	    unless (exists $perm_args{$arg}) {
		croak("ARG. ERROR: $arg isnt permited arg. for run_njtrees()");
	    }
	    else {
		my $val = $args_href->{$arg};
		my $regexp = '^' . $perm_args{$arg} . '$';
		if ($val !~ m/$regexp/i) {
		    croak("ARG. ERROR: $arg has a non-permited value ($val)")
		}
	    }
	}
    }

    ## Get outgroup if it is defined and delete from arguments

    my $outgroup;
    if (defined $args_href->{outgroup_strain}) {	
	$outgroup = delete($args_href->{outgroup_strain});    	
    }

    ## But outgroup can not be used for UPGMA

    if (defined $args_href->{type}) {
	if ($args_href->{type} =~ m/UPGMA/i) {
	    undef($outgroup);
	}
    }

    my @args = ();
    foreach my $key (keys %{$args_href}) {
	push @args, ($key, $args_href->{$key});
    }

    ## Get the distances and the clusters from the object

    my %dists = %{$self->get_distances()};
    my %clusters = %{$self->get_clusters()};
    my %strains = %{$self->get_strains()};    
    
    ## And now it will run one tree per distance and set tree in seqfam object

    my $a = 0;
    my $t = scalar( keys %dists );

    ## Define the failed array
    
    my @failed = ();

    foreach my $cluster_id (sort keys %dists) {

	$a++;
	## After check, create the array and the factory
	## It will create a new factory per tree (to be able to use
	## tools like outgroups)
    
	my $factory = Bio::Tools::Run::Phylo::Phylip::Neighbor->new(@args);

	my $distobj = $dists{$cluster_id};
	
	if (defined $distobj && scalar(@{$distobj->names()}) > 1) {

	    ## It will replace the ids before run the trees for an index

	    my %equivnames = ();
	    my %revnames = ();
	    my @newnames_list = ();
	    my @oldnames_list = ();
	    my $i = 1;

	    ## First, create the equiv. hash

	    foreach my $name (@{$distobj->names()}) {
		$equivnames{$i} = $name;
		$revnames{$name} = $i;
		push @newnames_list, $i;
		push @oldnames_list, $name;
		$i++;
	    }	    

	    ## Second, replace in the matrix (names and indexes) 
	    ## the names per i's
	    
	    my $mtx_href = $distobj->_matrix();
	    foreach my $i_name (keys %{$mtx_href}) {
		my $j_href = $mtx_href->{$i_name};
	    
		foreach my $j_name (keys %{$j_href}) {
		    $j_href->{$revnames{$j_name}} = delete($j_href->{$j_name});
		}
		$mtx_href->{$revnames{$i_name}} = delete($mtx_href->{$i_name});
	    }
 	
	    $distobj->names(\@newnames_list);

	    ## Now it will run the tree

	    my $seqfam = $clusters{$cluster_id};

	    if (defined $outgroup) {

		my $outgroup_id = _get_outgroup_id(
		    {
			seqfam    => $seqfam,
			strains   => \%strains,
			reference => $outgroup,
		    }
		    );
		if (defined $outgroup_id) {
		    my $outgroup_equiv = $revnames{$outgroup_id};
		    if (defined $outgroup_equiv) {
			$factory->outgroup($outgroup_equiv);
		    }
		}
	    }

	    if ($self->is_on_reportstatus) {
		print_parsing_status($a, $t, 
				     "\t\tPerc. of trees calculated:",
				     $cluster_id,
		    );
	    }

	    my ($tree) = $factory->run($distobj);

	    if (defined $tree) {
		$tree->id($cluster_id);
	    
		## Third, replace in the tree the nodes names for the righ ones

		my @nodes = $tree->get_nodes();
		foreach my $node (@nodes) {
		    if (defined $node->id()) {
			my $old_node_id = $node->id();
			$node->id($equivnames{$old_node_id});
		    }
		}

		$seqfam->tree($tree);
	    }
	    else {
		push @failed, $cluster_id;
	    }

	    ## Forth, replace the matrix names by the originals.
	
	    my $mtx_href2 = $distobj->_matrix();
	    foreach my $x_name (keys %{$mtx_href2}) {
		my $y_href = $mtx_href2->{$x_name};
		
		foreach my $y_name (keys %{$y_href}) {
		    $y_href->{$equivnames{$y_name}} = 
			delete($y_href->{$y_name});
		}
		$mtx_href2->{$equivnames{$x_name}} = 
		    delete($mtx_href2->{$x_name});
	    }
	    
	    $distobj->names(\@oldnames_list);
	}
    }
    return @failed;
}


=head2 run_mltrees

  Usage: $phygecluster->run_mltrees($arg_href);

  Desc: Calculates every tree for the distances contained into the SeqGeCluster
        object and load it into Bio::Cluster::SequenceFamily object using 
        phyml program

  Ret: None

  Args: $args_href, a hash reference with the following options:
        phyml => {}, $hash ref with phyml arguments (it will use phyml program)
        (for more information: 
        http://www.atgc-montpellier.fr/phyml/usersguide.php)
        dnaml => {}, $hash ref with phylip dnaml arguments,
        outgroup_strain => $strain, a scalar (a strain name to be as outgroup)
        (usable only with dnaml option)

  Side_Effects: Died if the arguments are wrong.
                
  Example: $phygecluster->run_mltrees($arg_href);

=cut

sub run_mltrees {
    my $self = shift;
    my $args_href = shift;

    my %perm_args = ( 
	phyml           => 'HASH',
	dnaml           => 'HASH',
	outgroup_strain => '\w+',
	);

    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ARG. ERROR: Arg. supplied to run_mltrees() arent hashref");
	}

	foreach my $arg (keys %{$args_href}) {
	    unless (exists $perm_args{$arg}) {
		croak("ARG. ERROR: $arg isnt permited arg. for run_mltrees()");
	    }
	    else {
		my $val = $args_href->{$arg};
		my $regexp = '^' . $perm_args{$arg};
		if ($val !~ m/$regexp/i) {
		    croak("ARG. ERROR: $arg has a non-permited value ($val)")
		}
	    }
	}
    }

    ## Default parameters:

    my %runargs = ();
    if (defined $args_href->{phyml}) {
	%runargs = %{$args_href->{phyml}};
	unless (exists $runargs{-data_type}) {
	    $runargs{-data_type} = 'nt';
	}
    }
    elsif (defined %{$args_href->{dnaml}}) {
	%runargs = %{$args_href->{dnaml}};
    }
    else {
	$args_href->{dnaml} = { quiet => 1 };
	%runargs = %{$args_href->{dnaml}};
    }

    ## And now it will run one tree per alignment
    ## Factory only can deal with one tree per run... so it is necessary
    ## redo de factory as many times as trees to create.

    my %clusters = %{$self->get_clusters()};
    my %strains = %{$self->get_strains()};

    ## Define failed array

    my @failed = ();

    my $a = 0;
    my $t = scalar( keys %clusters );

    foreach my $cluster_id (sort keys %clusters) {

	$a++;
	my $seqfam = $clusters{$cluster_id};
	my $align = $seqfam->alignment;
	
	if (defined $align) {

	    my $seqn = $align->num_sequences();

	    my %seqids = ();
	    my %revseqids = ();
	    my $i = 1;
	    foreach my $seqobj ($align->each_seq()) {

		my $seqid = $seqobj->display_id();
		$seqids{$i} = $seqid;
		$revseqids{$seqid} = $i;
		$align->remove_seq($seqobj);
		$seqobj->display_id($i);
		$align->add_seq($seqobj);
		$i++;
	    }

	    my $factory;
	    if (defined $args_href->{phyml}) {
		if (defined $args_href->{outgroup_strain}) {
		    my $err = "ERROR: outgroup_strain argument only can be ";
		    $err .= "used with dnaml option for run_mltree function";
		    croak($err);
		}
		$factory = Bio::Tools::Run::Phylo::Phyml->new(%runargs);
	    }
	    else {
		if (defined $args_href->{outgroup_strain}) {
		    my $outgroup_id = _get_outgroup_id(
			{
			    seqfam    => $seqfam,
			    strains   => \%strains,
			    reference => $args_href->{outgroup_strain},
			}
			);
		    if (defined $outgroup_id) {
			my $outgroup_idx = $revseqids{$outgroup_id};
			$runargs{OUTGROUP} = $outgroup_idx;
		    }
		}
		if ($seqn > 2) {
		    $factory = Bio::Tools::Run::Phylo::Phylip::Dnaml->new(
			%runargs);
		}
	    }

	    if (defined $factory) {

		if ($self->is_on_reportstatus) {
		    print_parsing_status($a, $t, 
					 "\t\tPerc. of trees calculated:",
					 $cluster_id,
			);
		}

		my ($tree) = $factory->run($align);	
	    	    
		if (defined $tree) {

		    $tree->id($cluster_id);

		    my @nodes = $tree->get_leaf_nodes();
		    foreach my $node (@nodes) {		
			my $old_node_id = $node->id();
			$old_node_id =~ s/'//g;  ## Some methods add ' to id
			$node->id($seqids{$old_node_id});
		    }
		    
		    $seqfam->tree($tree);
		}
		else {
		    push @failed, $cluster_id;
		}
	    }

	    ## Finally it will replace the ids of the alignments back 
	    foreach my $seqobj ($align->each_seq()) {
		$align->remove_seq($seqobj);
		my $oldid = $seqobj->display_id();
		$seqobj->display_id($seqids{$oldid});
		$align->add_seq($seqobj);
	    }

	}
    }
    return @failed;
}




######################
## PRUNE FUNCTIONS ###
######################


=head2 prune_by_align

  Usage: my %removed_clusters = $phygecluster->prune_by_align($arg_href)

  Desc: Remove clusters that have not some conditions
        derived from the align object

  Ret: A hash with the sequencefamilies objects removed from the object 
       (key=cluster_id and value=Bio::Cluster::SequenceFamily object) 
       (also modify the PhyGeCluster, Bio::Cluster::SequenceFamily and 
       Bio::SimpleAlign objects)

  Args: A hash reference with the following parameters:
        { functionname => [ condition => integer ] }
        functionnames could be: score, length, num_residues, num_sequences
        or percentage_identity
        
  Side_Effects: Died if some of the parameters are wrong.
              
  Example:  $phygecluster->prune_by_align(
                             { num_sequences => ['<',4], 
                               length        => ['<', 100],
			     });


=cut

sub prune_by_align {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None args. were suplied to prune_by_align()");

    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Argument used for prune_by_align is not hashref");
    }

    ## Check the arguments

    my %valid_args = (
	score               => 'ARRAY', 
	length              => 'ARRAY',  
	num_residues        => 'ARRAY', 
	num_sequences       => 'ARRAY',
        percentage_identity => 'ARRAY',
	);

    foreach my $argkey (keys %{$args_href}) {
	
	unless (exists $valid_args{$argkey}) {
	    my $err1 = "ARG. ERROR: $argkey is not valid key argument for ";
	    $err1 .= "prune_by_align() function";
	    croak($err1);
	}
	else {
	    my $argvar = $args_href->{$argkey};
	    unless (ref($argvar) eq $valid_args{$argkey}) {
		my $err2 = "ARG. ERROR: $argvar is not a valid value argument";
		$err2 .= " (an array ref.) for prune_by_align() function";
		croak($err2);
	    }
	}
    }

    ## Now it will check each condition for the arguments
    
    my %rmclusters = ();

    my %clusters = %{$self->get_clusters()};
    my $CL = scalar(keys %clusters);
    my $cl = 0;

    foreach my $clid (keys %clusters) {
	
	my $rmcluster = 0;
	my $seqfam = $clusters{$clid};
	my $align = $seqfam->alignment();
	
	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($CL,$cl,"\t\tPerc. of clusters pruned:",$clid);
	}

	if (defined $align) {
	    foreach my $function (keys %{$args_href}) {
		my $seqfam_value = $align->$function;
		my $condition = $args_href->{$function}->[0] || 
		    croak("ERROR: None condition was detailed for $function");
		my $filtvalue = $args_href->{$function}->[1] ||
		    croak("ERROR: None filter val. was detailed for $function");
	   
		unless ($filtvalue =~ m/^\d+$/) {
		    croak("ERROR: filter value $filtvalue is not an integer");
		}
		## Now it will detail the list of comparissons

		if ($condition eq '<') {
		    if ($seqfam_value < $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '<=') {
		    if ($seqfam_value <= $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '==') {
		    if ($seqfam_value == $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '>=') {
		    if ($seqfam_value >= $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '>') {
		    if ($seqfam_value > $filtvalue) {
			$rmcluster = 1;
		    }
		}
		else {
		    my $err3 = "ERROR: The condition $condition is not a valid";
		    $err3 .= " condition (<, <=, ==, >= or >)";
		    croak($err3);
		}	    
	    }
	}

	if ($rmcluster == 1) {
	    my $rmval = $self->remove_cluster($clid);
	    $rmclusters{$clid} = $rmval;
	}
    }

    ## If the prune has removed something it should remove also distances
    ## and overlaps (alignment and trees are stored in the cluster that has
    ## been removed)

    if (scalar(keys %rmclusters) > 0) {
		
	my %dist = %{$self->get_distances()};
	my %bootstr = %{$self->get_bootstrapping()};

	foreach my $rmclid (keys %rmclusters) {
	    
            ## 1) Remove distances 
	    
	    if (exists $dist{$rmclid}) {
		delete($dist{$rmclid});
	    }
	    
            ## 2) Remove bootstrap
	    
	    if (exists $bootstr{$rmclid}) {
		delete($bootstr{$rmclid});
	    }
	}
    }
    return %rmclusters;
}


=head2 prune_by_strains

  Usage: my ($rm_clusters_href, $rm_members_href)
             = $phygecluster->prune_by_strains($args_href)

  Desc: Remove sequence members and clusters that have not some conditions
        derived from the strains of the sequences of the alignment

  Ret: A two hash references with:
       1) the sequencefamilies objects removed from the object 
          (key=cluster_id and value=Bio::Cluster::SequenceFamily object)
       2) the clusters with the list of members removed (array references)
          (also modify the PhyGeCluster, Bio::Cluster::SequenceFamily and 
          Bio::SimpleAlign objects)

  Args: A hash reference with:
        composition  => $href with key=strain, value=count
        min_distance => $aref_of_aref_pairs defining distances
        max_distance => $aref_of_aref_pairs defining distances
        
  Side_Effects: Died if some of the parameters are wrong.
                When as result of the prune arguments a cluster is deleted, 
                it also delete distances and bootstrapping data for that 
                cluster. 
                When as result of the rpune arguments, some members of a 
                cluster, it will remove them from the cluster and the alignment
                also it will remove the distances and the bootstrapping for 
                them.
              
  Example:  ## To get three sequences for strains A, B and C:
            $phygecluster->prune_by_strains({ 
                                             composition => {'A' => 1, 
                                                             'B' => 1, 
                                                             'C' => 1,
                                                            },
                                            });

            ## To get three sequences where A is close to B and C
            $phygecluster->prune_by_strains({ 
                                              composition => {'A' => 1, 
                                                              'B' => 1, 
                                                              'C' => 1,
                                                             },
                                              min_distance => [
                                                               ['A','B'],
                                                               ['A','C'],
                                                              ]
                                            });
              
            ## To get four sequences where A is close to B and C to D
            $phygecluster->prune_by_strains({
                                              composition => {'A' => 1, 
                                                              'B' => 1, 
                                                              'C' => 1,
                                                              'D' => 1,
                                                            },
                                              min_distance => [
                                                                ['A','B'],
                                                                ['C','D']
                                                              ]
                                            });
             ## To get five sequences A close to B, another A close to C, and
             ## a random D. A and A' should be close to
             $phygecluster->prune_by_strains({
                                        composition  => {'A' => 2, 
                                                         'B' => 1, 
                                                         'C' => 1,
                                                         'D' => 1,
                                                        },
                                        min_distance => [    
                                                          ['A','B'],
                                                          ['A','C'],
                                                          ['A','A'],
                                                        ]
                                        });

=cut

sub prune_by_strains {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None hash ref. argument was used prune_by_strains");

    ## Check the arguments
   
    my %args;
    unless(ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: $args_href is not a hash ref. for prune_by_strains");
    }
    else {
	%args = %{$args_href};
    }

    unless($args{'composition'}) {
	croak("ARG. ERROR: No composition arg. was used for prune_by_strains");
    }

    my %valid_constr = ( composition  => 'HASH', 
		 	 min_distance => 'ARRAY', 
			 max_distance => 'ARRAY',
	);

    foreach my $constr (keys %args) {
	unless (exists $valid_constr{$constr}) {
	    croak("ERROR: Constraint $constr does not avail. prune_by_strains");
	}
	else {
	    unless (ref($args{$constr}) eq $valid_constr{$constr}) {
		croak("ERROR: Value $constr isnt $valid_constr{$constr} ref.");
	    }
	}
    }

    ## Define the variables that are going to store the removed clusters
    ## and the member removed from some clusters.

    my %rm_clusters = ();
    my %rm_members = ();

    ## Check that exists strains

    my %strains = %{$self->get_strains()};

    my $strain_n = scalar(keys %strains);
    if ($strain_n < 1) {
	croak("ERROR: No strains were loaded into PhyGeCluster object.");
    }

    ## Define composition hash and get the number of sequences expected
    
    my $comp = Strain::Composition->new(
	{ 
	    strains     => $self->get_strains(),
	    composition => $args{'composition'}, 
	}
	);

    ## Define


    ## Get the distances
    
    my %dist = %{$self->get_distances()};
    my $dist_n = scalar(keys %dist);
    if ($dist_n < 1) {
	croak("ERROR: No distances were loaded into PhyGeCluster object.");
    }

    ## Get the bootstrapping clusters from tyhe object to be able to remove
    ## them from the object

    my %bootstr = %{$self->get_bootstrapping()};

    ## Now it will order the distances according each of the strains.

    my %clusters = %{$self->get_clusters()};
    my $CL = scalar( keys %clusters);
    my $cl = 0;

    foreach my $clid (keys %clusters) {
	
	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($CL,$cl,"\t\tPerc. of clusters pruned:",$clid);
	}

	my $seqfam = $clusters{$clid};
	
	## Define the array to select the seq_ids
	my %selected_mb = ();

	## Apply the selection if exists defined the distance

	my $distmx = $dist{$clid};
	if (defined $distmx) {

	    ## Now transform the distance matrix into a serie of
	    ## arrays for each strain pair with seqnames as elements

	    ## 1) Create a hash with pair/distance

	    my %distpr = ();
	    my %comppr = ();
	    my %strpr = ();
	    
	    my $row = 0;
	    foreach my $seqid_a ($distmx->row_names) {
		
		$row++;
		my $col = 0;

		foreach my $seqid_b ($distmx->column_names) {

		    $col++;
		    if ($row > $col) {  ## Skip the half of the matrix
			
			my @pair = sort(($seqid_a, $seqid_b));
			my $pair = join(',', @pair);
			my $dist_val = $distmx->get_entry($seqid_a, $seqid_b);
			
			$distpr{$pair} = $dist_val;
			$comppr{$pair} = \@pair;
			$strpr{$pair} = [$strains{$seqid_a},$strains{$seqid_b}];
		    }
		}
	    }

	    
	    ## 2) Create a hash depending of the constrain

	    my @ordpairs = ();
	   
	    if (exists $args{min_distance} || exists $args{max_distance}) {

		my @dpairs = sort { $distpr{$a} <=> $distpr{$b} } keys %distpr;
		my @constpairs;

		if (exists $args{max_distance}) {  ## reverse if is max

		    @dpairs = reverse(@dpairs);
		    @constpairs = @{$args_href->{max_distance}};
		}
		else {
		    @constpairs = @{$args_href->{min_distance}};
		}
		
		foreach my $constpair (@constpairs) {
		    
		    my @non_selected = ();

		    my $constline = join(',', sort @{$constpair});

		    while (scalar(@dpairs) > 0) {
			
			my $distpair = shift(@dpairs);
			my $distline = join(',', sort @{$strpr{$distpair}});
			
			if ($distline eq $constline) {
			    push @ordpairs, $distpair;
			}
			else {
			    push @non_selected, $distpair;
			}
		    }
		    push @dpairs, @non_selected;
		}
		push @ordpairs, @dpairs;

	    }
	    else {
		@ordpairs = keys %distpr;
	    }
	    

	    ## 3) Select members according the order

	    my $complete = $comp->is_complete();
		
	    while( $complete == 0 && scalar(@ordpairs) > 0) {
		    
		my $pairname = shift(@ordpairs);  ## Remove one from the pair
		
		if (defined $pairname) {
		    
		    my @seqpair = @{$comppr{$pairname}};

		    foreach my $seqid (@seqpair) {

			$comp->add_member($seqid);
			$complete = $comp->is_complete();
		    }
		}
	    }
	}

	## Now it will remove all the clusters where the composition is not
	## complete.

	if ($comp->is_complete()) {
	   
	    ## Get the members and delete from composition object
	    
	    my %sel_members = ();
	    my %members = $comp->delete_members();
	    foreach my $str (keys %members) {
		
		foreach my $member (@{$members{$str}}) {

		    $sel_members{$member} = $str;
		}
	    }

	    ## define the array to store removed members

	    my @rm_members = ();

	    ## 1) Remove the sequence from the alignment that has not been 
            ##    selected

	    my $align = $seqfam->alignment();
	    if (defined $align) {
		foreach my $alignmember ( $align->each_seq() ) {
		    my $member_id = $alignmember->display_id();
		    unless (exists $sel_members{$member_id}) {
			$align->remove_seq($alignmember);
		    }
		}
	    }

	    ## 2) Remove from the SequenceFamily object

	    my @fam_members = $seqfam->get_members();

	    ## SequenceFamily object has not a function to remove 
	    ## members one by one, it remove all the members, so
	    ## this code will add the selected members to the object
	    ## after the removing of all the members
	    
	    $seqfam->remove_members();

	    foreach my $fam_member (@fam_members) {
		my $fmember_id = $fam_member->display_id();
		unless (exists $sel_members{$fmember_id}) {
		    push @rm_members, $fmember_id;
		}
		else {
		    $seqfam->add_members([$fam_member]);
		}
	    }
	    $rm_members{$clid} = \@rm_members;

	    ## The trees, distances and bootstrapping
	    ## don't make sense once some members have been removed

	    if (scalar(@rm_members) > 0) {
		my $tree = $seqfam->tree();
		if (defined $tree) {
		    $seqfam->tree(undef);
		}
		my $rm_distmtx = delete($self->get_distances()->{$clid});
		my $rm_boots = delete($self->get_bootstrapping()->{$clid});
	    }
	}
	else {

	    ## Delete the comp
	    my %members = $comp->delete_members();

	    my $cluster_removed = $self->remove_cluster($clid);
	    my $rm_distmtx = delete($self->get_distances()->{$clid});
	    my $rm_boots = delete($self->get_bootstrapping()->{$clid});
	    
	    $rm_clusters{$clid} = $cluster_removed;
	}
    }

    return (\%rm_clusters, \%rm_members);
}

=head2 prune_by_overlaps

  Usage: my ($rm_clusters_href, $rm_members_href)
             = $phygecluster->prune_by_overlaps($args_href)

  Desc: Remove sequence members and clusters that have not some conditions
        derived from the overlaps count by strains. It takes the best overlap
        and from here add new sequence from the alignment and calculate the
        overlap length and get the best. It repeats this process until get all
        the composition conditions or spend all the possible combinations 
        without results.

  Ret: A two hash references with:
       1) the sequencefamilies objects removed from the object 
          (key=cluster_id and value=Bio::Cluster::SequenceFamily object)
       2) the clusters with the list of members removed (array references)
          (also modify the PhyGeCluster, Bio::Cluster::SequenceFamily and 
          Bio::SimpleAlign objects)

  Args: A hash reference with:
        composition  => $href with key=strain, value=count.
        method       => length, identity or ovlscore (ovlscore by default)
                        (use a ovlscore based in: length * (identity/100)^2).
        evalseed     => $int, an integer, number of seeds evaluated to find
                        the better set of overlaps.    
        filter       => $href with key=length/identity, value=cutoff value.
        trim         => $boolean (0|1 to disable|enable)... enable by default.
        removegaps   => $boolean (0|1 to disable|enable)... enable by default.
                        
        (to cut the alignment and get the region defined by the overlap)
        
  Side_Effects: Died if some of the parameters are wrong.
              
  Example: my ($rm_clust_hf, $rm_memb_hf) = 
                       $phygecluster->prune_by_overlaps({random => 4 });

=cut

sub prune_by_overlaps {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: No hash ref. argument was used prune_by_overlaps");

    ## Check the arguments hashref is an hashref.
   
    my %args;
    unless(ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: $args_href isnt an hash ref. for prune_by_overlaps");
    }
    else {
	%args = %{$args_href};
    }

    ## Arguments checking

    my %permargs = (
	composition => {},
	method      => '(length|identity|ovlscore)',
	evalseed    => '\d+',
	filter      => {},
	trim        => '(1|0)',
	removegaps  => '(1|0)',
	);
    
    foreach my $karg (keys %args) {
	unless (exists $permargs{$karg}) {
	    croak("ERROR: $karg is a non-permitted arg. for prune_by_overlaps");
	}
	else {
	    if (ref($permargs{$karg})) {
		if (ref($args{$karg}) ne ref($permargs{$karg}) ) {
		    croak("ERROR: $karg has a non-valid value ($args{$karg})");
		}
	    }
	    else {
		if ($args{$karg} !~ m/^$permargs{$karg}$/) {
		    croak("ERROR: $karg has a non-valid value ($args{$karg})");
		}
	    }
	}
    }
    
    ## Check the mandatory arguments
    
    unless (exists $args{composition}) {
	croak("ERROR: No composition arg. was used for prune_by_overlaps()");
    }

    ## Check the arguments with default values
    
    my %defargs = (
	method      => 'ovlscore',
	evalseed    => 1,
	trim        => 1,
	removegaps  => 0,
	);
    
    foreach my $defarg (keys %defargs) {
	unless (exists $args{$defarg}) {
	    $args{$defarg} = $defargs{$defarg};
	}
    }

    ## Load the composition into a composition object, strains incluided

    my %str = %{$self->get_strains()};
    my $comp = Strain::Composition->new(
	{ 
	    strains     => \%str,
	    composition => $args{composition}, 
	});

    ## Define the removed hashes rmcls (removed cluster) and rmmem (removed
    ## members).

    my %rmcls = ();
    my %rmmem = ();

    ## After check the variables it will get clusters and overlaps

    my $cls_href = $self->get_clusters();
    my $CL = scalar( keys %{$cls_href} );
    my $cl = 0;

    foreach my $clid (sort keys %{$cls_href}) {

	## Define the best align var to catch the best align at the end of the
	## block (if there are any)
	
	my $best_aln;

	my $seqfam = $cls_href->{$clid};
	my $align = $seqfam->alignment();	

	## Print status (if the switch is enabled)
	
	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($cl,$CL,"\t\tPerc. of clusters pruned:",$clid);
	}
	
	## Create a complete remove switch

	my $complete_rm = 0; 

	## Work only for seqfams with alignments
       		
	if (defined $align ) {
	   
	    ## Check that the alignment has the right composition
	    foreach my $memb ($align->each_seq()) {
		
		$comp->add_member($memb->display_id());
	    }

	    if ($comp->is_complete()) {         ## Skip if it doesnt have 
	                                        ## enough seqs for comp
	    
		## Reset member composition
		$comp->delete_members();
		
		my $mtx = Bio::Align::Overlaps::calculate_overlaps($align);
		
		my @seedargs = ($mtx, $args{method}, $args{filter});
		my @seeds_arefs = Bio::Align::Overlaps::seed_list(@seedargs);

		## Choose a seed that for comp

		my @filtseeds = ();
		foreach my $seed_aref (@seeds_arefs) {
		    my $is_comp = 0;
		    foreach my $seed (@{$seed_aref}) {
			if (defined $comp->add_member($seed)) {
			    $is_comp++;
			}
		    }
		    if ($is_comp == 2) {     ## If both are in the comp
			push @filtseeds, $seed_aref;
		    }
		    $comp->delete_members(); ## Reset member composition
		}

		## Evaluate as many seeds as evalseed argument

		my %seedpath = ();

		my $curr_seedeval = 0;
		my $seedn =  scalar(@filtseeds);
		while($curr_seedeval < $args{evalseed} && $seedn > 0) {

		    my $seed_aref = shift(@filtseeds);
		    $seedn = scalar(@filtseeds);
		    my @seed = sort( @{$seed_aref});
		    
		    ## Get start and end for this seed
		    my $seed_entry = $mtx->entry($seed[0], $seed[1]);
		    my $seed_st = $seed_entry->{start};
		    my $seed_en = $seed_entry->{end};

		    ## Calculate the overseeds (extensions) for this seed
		    my @ov = ($align, \@seed, $seed_st, $seed_en);
		    my %ovseed = Bio::Align::Overlaps::calculate_overseeds(@ov);
		
		    my @extargs = (\%ovseed, $args{method}, $args{filter});
		    my @exts = Bio::Align::Overlaps::extension_list(@extargs);
		    
		    ## Add seeds and extension to comp
		    
		    $comp->add_member($seed[0]);
		    $comp->add_member($seed[1]);

		    while($comp->is_complete() == 0 && scalar(@exts) > 0) {
			$comp->add_member(shift(@exts));
		    }

		    ## Get the members and reset comp
		    ## Add the member to a seed path

		    if ($comp->is_complete()) {
			
			my @selectedmembers = ();
			my %members = $comp->delete_members();
			foreach my $str (keys %members) {
			    push @selectedmembers, @{$members{$str}};
			}

			## Check that the members all the members overlap

			my @ovl = ($align, \@selectedmembers);
			my %govl = Bio::Align::Overlaps::global_overlap(@ovl);

			if ($govl{length} > 0) {

			    $seedpath{$curr_seedeval} = \@selectedmembers;
			}
		    }
		    else {
			$comp->delete_members();
		    }

		    $curr_seedeval++;
		}

		## Now it wll evaluate the different paths to get the best
		## according the method used.

		my %sescore = ();
		my %sealign = ();
		
		foreach my $sp (sort keys %seedpath) {

		    my $oal = { align    => $align, 
				members  => $seedpath{$sp},
				trim     => $args{trim},
				gapscomp => $args{removegaps},
				filter   => $args{filter},
		    };
		    
		    my $nwaln = Bio::Align::Overlaps::make_overlap_align($oal);
		    
		    if (defined $nwaln) {
			$sealign{$sp} = $nwaln;
		    
			my $na_len = $nwaln->length();
			my $na_ide = $nwaln->percentage_identity();
			my $na_ovlsc = $na_len * ($na_ide/100) * ($na_ide/100);
		    
			## Score the alignment according method
			
			if ($args{method} eq 'length') {
			    $sescore{$sp} = $na_len;
			}
			elsif ($args{method} eq 'identity') {
			    $sescore{$sp} = $na_ide;
			}
			else {
			    $sescore{$sp} = $na_ovlsc;
			}
		    }
		}

		## Get the best
		
		if (scalar(keys %sescore) > 0) {

		    my @al = sort {$sescore{$b} <=> $sescore{$a}} keys %sescore;
		    $best_aln = $sealign{$al[0]};
		}
		
		unless (defined $best_aln) {
		    $complete_rm = 1;
		}
		else {
		    
		}				
	    }
	    else {
		$complete_rm = 1;
		
                ## Reset composition
		$comp->delete_members();
	    }
	}
	else {
	    $complete_rm = 1;
	}
    
	## Now it has two options
	## a) the alignment has not meet the comp. conditions, so all the
	##    cluster should be removed.
       
	if ($complete_rm == 1) {
	    
	    my $rm_seqfam = delete($cls_href->{$clid});
	    my $rm_dismtx = delete($self->get_distances()->{$clid});
	    my $rm_bootst = delete($self->get_bootstrapping()->{$clid});
	    
	    $rmcls{$clid} = $rm_seqfam;
	}

	## Now it has two options
	## b) the alignment meet the comp. conditions, so the alignment will
	##    be replaced by the best alignment and the members that are not
        ##    in this new alignment will be removed

	else {


	    ## 1) Remove members from Sequence Family

	    my $seqfam = $cls_href->{$clid};
	    
	    my %selected_mb = ();
	    my @bmembers = $best_aln->each_seq();
	    foreach my $bmember (@bmembers) {
		$selected_mb{$bmember->display_id()} = 1;
	    }

	    my @rm_members = ();

	    my @seqfam_members = $seqfam->remove_members();
	    foreach my $seqfam_mb (@seqfam_members) {
		if (exists $selected_mb{$seqfam_mb->display_id()}) {
		    $seqfam->add_members([$seqfam_mb]);
		}
		else {
		    push @rm_members, $seqfam_mb;
		}
	    }
	    
	    $rmmem{$clid} = \@rm_members;
	    
	    ## 2) Set alignment with the best alignment

	    $seqfam->alignment($best_aln);

	    ## 3) The alignment has change so distances and bootstrapping
	    ##    don't have sense
	    
	    my $tree = $seqfam->tree();
	    if (defined $tree) {
		$seqfam->tree(undef);
	    }
	    my $rmdistmtx = delete($self->get_distances()->{$clid});
	    my $rmboo = delete($self->get_bootstrapping()->{$clid});
	}
    }
	   
    return (\%rmcls, \%rmmem);
}

=head2 prune_by_bootstrap

  Usage: my %removed_clusters = $phygecluster->prune_by_bootstrap($arg_href)

  Desc: Remove clusters that have not some conditions
        derived from the bootstrap values object

  Ret: A hash with the sequencefamilies objects removed from the object 
       (key=cluster_id and value=Bio::Cluster::SequenceFamily object) 
       (also modify the PhyGeCluster, Bio::Cluster::SequenceFamily and 
       Bio::SimpleAlign objects)

  Args: A scalar with the bootstrap value used as cutoff.
        
  Side_Effects: Died if some of the parameters are wrong.
              
  Example:  $phygecluster->prune_by_bootstrap(90)

=cut

sub prune_by_bootstrap {
    my $self = shift;
    my $bootval = shift ||
	croak("ERROR: No bootstrap value was supplied to prune_by_bootstrap()");

    unless ($bootval =~ m/^\d+$/) {
	croak("ERROR: bootstrap value isnt a int. for prune_by_bootstrap()");
    }
    
    my %rem_cls = ();

    ## Get hashref with clusters

    my $cls_href = $self->get_clusters();
    my $cls_dist = $self->get_distances();

    ## First get bootstrapping

    my %boots = %{$self->get_bootstrapping()};
    my $CL = scalar(keys %boots);
    my $cl = 0;

    foreach my $clid (sort keys %boots) {
	
	$cl++;
	if ($self->is_on_reportstatus) {
	    print_parsing_status($CL,$cl,"\t\tPerc. of clusters pruned:",$clid);
	}

	my $consensus = $boots{$clid};
	my @nodes = $consensus->get_nodes();

	my $nopass = 0;
	foreach my $node (@nodes) {
	
	    my $nodboot = $node->bootstrap() || $node->branch_length();

	    if (defined $nodboot) { ## It can be the root
		if ($nodboot < $bootval) {
		    $nopass = 1;
		}
	    }
	}

	## If it has a node with a bootstrap value under the cutoff, it 
	## will remove it.

	if ($nopass == 1) {
	    $rem_cls{$clid} = $self->remove_cluster($clid);
	    
	    delete($cls_dist->{$clid});
	    delete($boots{$clid});
	}
    }

    return %rem_cls;
}



####
1; #
####
