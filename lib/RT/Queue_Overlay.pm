# $Header: /raid/cvsroot/rt/lib/RT/Queue.pm,v 1.4 2002/01/11 00:01:02 jesse Exp $

=head1 NAME

  RT::Queue - an RT Queue object

=head1 SYNOPSIS

  use RT::Queue;

=head1 DESCRIPTION


=head1 METHODS

=begin testing 

use RT::Queue;

=end testing

=cut

no warnings qw(redefine);

use vars qw(@STATUS @ACTIVE_STATUS @INACTIVE_STATUS);
use RT::Groups;

@ACTIVE_STATUS = qw(new open stalled);
@INACTIVE_STATUS = qw(resolved rejected deleted);
@STATUS = (@ACTIVE_STATUS, @INACTIVE_STATUS);

# $self->loc('new'); # For the string extractor to get a string to localize
# $self->loc('open'); # For the string extractor to get a string to localize
# $self->loc('stalled'); # For the string extractor to get a string to localize
# $self->loc('resolved'); # For the string extractor to get a string to localize
# $self->loc('rejected'); # For the string extractor to get a string to localize
# $self->loc('deleted'); # For the string extractor to get a string to localize



# {{{ ActiveStatusArray

=head2 ActiveStatusArray

Returns an array of all ActiveStatuses for this queue

=cut

sub ActiveStatusArray {
    my $self = shift;
    return (@ACTIVE_STATUS);
}

# }}}

# {{{ InactiveStatusArray

=head2 InactiveStatusArray

Returns an array of all InactiveStatuses for this queue

=cut

sub InactiveStatusArray {
    my $self = shift;
    return (@INACTIVE_STATUS);
}

# }}}

# {{{ StatusArray

=head2 StatusArray

Returns an array of all statuses for this queue

=cut

sub StatusArray {
    my $self = shift;
    return (@STATUS);
}

# }}}

# {{{ IsValidStatus

=head2 IsValidStatus VALUE

Returns true if VALUE is a valid status.  Otherwise, returns 0

=for testing
my $q = RT::Queue->new($RT::SystemUser);
ok($q->IsValidStatus('new')== 1, 'New is a valid status');
ok($q->IsValidStatus('f00')== 0, 'f00 is not a valid status');

=cut

sub IsValidStatus {
    my $self  = shift;
    my $value = shift;

    my $retval = grep ( /^$value$/, $self->StatusArray );
    return ($retval);

}

# }}}

# {{{ IsActiveStatus

=head2 IsActiveStatus VALUE

Returns true if VALUE is a Active status.  Otherwise, returns 0

=for testing
my $q = RT::Queue->new($RT::SystemUser);
ok($q->IsActiveStatus('new')== 1, 'New is a Active status');
ok($q->IsActiveStatus('rejected')== 0, 'Rejected is an inactive status');
ok($q->IsActiveStatus('f00')== 0, 'f00 is not a Active status');

=cut

sub IsActiveStatus {
    my $self  = shift;
    my $value = shift;

    my $retval = grep ( /^$value$/, $self->ActiveStatusArray );
    return ($retval);

}

# }}}

# {{{ IsInactiveStatus

=head2 IsInactiveStatus VALUE

Returns true if VALUE is a Inactive status.  Otherwise, returns 0

=for testing
my $q = RT::Queue->new($RT::SystemUser);
ok($q->IsInactiveStatus('new')== 0, 'New is a Active status');
ok($q->IsInactiveStatus('rejected')== 1, 'rejeected is an Inactive status');
ok($q->IsInactiveStatus('f00')== 0, 'f00 is not a Active status');

=cut

sub IsInactiveStatus {
    my $self  = shift;
    my $value = shift;

    my $retval = grep ( /^$value$/, $self->InactiveStatusArray );
    return ($retval);

}

# }}}


# {{{ sub Create

=head2 Create

Create takes the name of the new queue 
If you pass the ACL check, it creates the queue and returns its queue id.

=cut

sub Create {
    my $self = shift;
    my %args = (
        Name              => undef,
        CorrespondAddress => '',
        Description       => '',
        CommentAddress    => '',
        InitialPriority   => "0",
        FinalPriority     => "0",
        DefaultDueIn      => "0",
        @_
    );

    unless ( $self->CurrentUser->HasSystemRight('AdminQueue') )
    {    #Check them ACLs
        return ( 0, $self->loc("No permission to create queues") );
    }

    unless ( $self->ValidateName( $args{'Name'} ) ) {
        return ( 0, $self->loc('Queue already exists') );
    }

    #TODO better input validation
    $RT::Handle->BeginTransaction();

    my $id = $self->SUPER::Create(%args);
    unless ($id) {
        $RT::Handle->Rollback();
        return ( 0, $self->loc('Queue could not be created') );
    }

    my $create_ret = $self->_CreateQueueGroups();
    unless ($create_ret) {
        $RT::Handle->Rollback();
        return ( 0, $self->loc('Queue could not be created') );
    }

    $RT::Handle->Commit();
    return ( $id, $self->loc("Queue created") );
}

# }}}

# {{{ sub Delete 

sub Delete {
    my $self = shift;
    return ( 0,
        $self->loc('Deleting this object would break referential integrity') );
}

# }}}

# {{{ sub SetDisabled

=head2 SetDisabled

Takes a boolean.
1 will cause this queue to no longer be avaialble for tickets.
0 will re-enable this queue

=cut

# }}}

# {{{ sub Load 

=head2 Load

Takes either a numerical id or a textual Name and loads the specified queue.
  
=cut

sub Load {
    my $self = shift;

    my $identifier = shift;
    if ( !$identifier ) {
        return (undef);
    }

    if ( $identifier !~ /\D/ ) {
        $self->SUPER::LoadById($identifier);
    }
    else {
        $self->LoadByCol( "Name", $identifier );
    }

    return ( $self->Id );

}

# }}}

# {{{ sub ValidateName

=head2 ValidateName NAME

Takes a queue name. Returns true if it's an ok name for
a new queue. Returns undef if there's already a queue by that name.

=cut

sub ValidateName {
    my $self = shift;
    my $name = shift;

    my $tempqueue = new RT::Queue($RT::SystemUser);
    $tempqueue->Load($name);

    #If we couldn't load it :)
    unless ( $tempqueue->id() ) {
        return (1);
    }

    #If this queue exists, return undef
    #Avoid the ACL check.
    if ( $tempqueue->Name() ) {
        return (undef);
    }

    #If the queue doesn't exist, return 1
    else {
        return (1);
    }

}

# }}}

# {{{ sub Templates

=head2 Templates

Returns an RT::Templates object of all of this queue's templates.

=cut

sub Templates {
    my $self = shift;

    my $templates = RT::Templates->new( $self->CurrentUser );

    if ( $self->CurrentUserHasRight('ShowTemplate') ) {
        $templates->LimitToQueue( $self->id );
    }

    return ($templates);
}

# }}}

# {{{ Dealing with custom fields

# {{{ CustomFields

=item CustomFields

Returns an RT::CustomFields object containing all global custom fields, as well as those tied to this queue

=cut

sub CustomFields {
    my $self = shift;

    my $cfs = RT::CustomFields->new( $self->CurrentUser );
    if ( $self->CurrentUserHasRight('SeeQueue') ) {
        $cfs->LimitToGlobalOrQueue( $self->Id );
    }
    return ($cfs);
}

# }}}

# }}}


# {{{ Routines dealing with watchers.

# {{{ _CreateQueueGroups 

=head2 _CreateQueueGroups

Create the ticket groups and relationships for this ticket. 
This routine expects to be called from Ticket->Create _inside of a transaction_

It will create four groups for this ticket: Requestor, Cc, AdminCc and Owner.

It will return true on success and undef on failure.

=begin testing

my $Queue = RT::Queue->new($RT::SystemUser); my ($id, $msg) = $Queue->Create(Name => "Foo",
                );
ok ($id, "Foo $id was created");
ok(my $group = RT::Group->new($RT::SystemUser));
ok($group->LoadQueueGroup(Queue => $id, Type=> 'Cc'));
ok ($group->Id, "Found the requestors object for this Queue");



ok ((my $add_id, $add_msg) = $Queue->AddWatcher(Type => 'Cc', Email => 'bob@fsck.com'), "Added bob at fsck.com as a requestor");
ok ($add_id, "Add succeeded: ($add_msg)");
ok(my $bob = RT::User->new($RT::SystemUser), "Creating a bob rt::user");
$bob->LoadByEmail('bob@fsck.com');
ok($bob->Id,  "Found the bob rt user");
ok ($Queue->IsWatcher(Type => 'Cc', PrincipalId => $bob->PrincipalId), "The Queue actually has bob at fsck.com as a requestor");;
ok ((my $add_id, $add_msg) = $Queue->DeleteWatcher(Type =>'Cc', Email => 'bob@fsck.com'), "Added bob at fsck.com as a requestor");
ok (!$Queue->IsWatcher(Type => 'Cc', Principal => $bob->PrincipalId), "The Queue no longer has bob at fsck.com as a requestor");;


$group = RT::Group->new($RT::SystemUser);
ok($group->LoadQueueGroup(Queue => $id, Type=> 'Cc'));
ok ($group->Id, "Found the cc object for this Queue");
$group = RT::Group->new($RT::SystemUser);
ok($group->LoadQueueGroup(Queue => $id, Type=> 'AdminCc'));
ok ($group->Id, "Found the AdminCc object for this Queue");

=end testing

=cut


sub _CreateQueueGroups {
    my $self = shift;

    my @types = qw(Cc AdminCc Requestor Owner);

    foreach my $type (@types) {
        my $type_obj = RT::Group->new($self->CurrentUser);
        my ($id, $msg) = $type_obj->CreateRoleGroup(Instance => $self->Id, 
                                                     Type => $type,
                                                     Domain => 'QueueRole');
        unless ($id) {
            $RT::Logger->error("Couldn't create a Queue group of type '$type' for ticket ".
                               $self->Id.": ".$msg);
            return(undef);
        }
     }
    return(1);
   
}


# }}}

# {{{ sub AddWatcher

=head2 AddWatcher

AddWatcher takes a parameter hash. The keys are as follows:

Type        One of Requestor, Cc, AdminCc

PrinicpalId The RT::Principal id of the user or group that's being added as a watcher
Email       The email address of the new watcher. If a user with this 
            email address can't be found, a new nonprivileged user will be created.

If the watcher you\'re trying to set has an RT account, set the Owner paremeter to their User Id. Otherwise, set the Email parameter to their Email address.

=cut

sub AddWatcher {
    my $self = shift;
    my %args = (
        Type  => undef,
        PrincipalId => undef,
        Email => undef,
        @_
    );

    # {{{ Check ACLS
    #If the watcher we're trying to add is for the current user
    if ( $self->CurrentUser->PrincipalId  eq $args{'PrincipalId'}) {
        #  If it's an AdminCc and they don't have 
        #   'WatchAsAdminCc' or 'ModifyTicket', bail
        if ( $args{'Type'} eq 'AdminCc' ) {
            unless ( $self->CurrentUserHasRight('ModifyQueueWatchers')
                or $self->CurrentUserHasRight('WatchAsAdminCc') ) {
                return ( 0, $self->loc('Permission Denied'))
            }
        }

        #  If it's a Requestor or Cc and they don't have
        #   'Watch' or 'ModifyTicket', bail
        elsif ( ( $args{'Type'} eq 'Cc' ) or ( $args{'Type'} eq 'Requestor' ) ) {

            unless ( $self->CurrentUserHasRight('ModifyQueueWatchers')
                or $self->CurrentUserHasRight('Watch') ) {
                return ( 0, $self->loc('Permission Denied'))
            }
        }
     else {
            $RT::Logger->warn( "$self -> AddWatcher got passed a bogus type");
            return ( 0, $self->loc('Error in parameters to Queue->AddWatcher') );
        }
    }

    # If the watcher isn't the current user 
    # and the current user  doesn't have 'ModifyTicket'
    # bail
    else {
        unless ( $self->CurrentUserHasRight('ModifyQueueWatcher') ) {
            return ( 0, $self->loc("Permission Denied") );
        }
    }

    # }}}

    return ( $self->_AddWatcher(%args) );
}

#This contains the meat of AddWatcher. but can be called from a routine like
# Create, which doesn't need the additional acl check
sub _AddWatcher {
    my $self = shift;
    my %args = (
        Type   => undef,
        Silent => undef,
        PrincipalId => undef,
        Email => undef,
        @_
    );


    my $principal = RT::Principal->new($self->CurrentUser);
    if ($args{'PrincipalId'}) {
        $principal->Load($args{'PrincipalId'});
    }
    elsif ($args{'Email'}) {

        my $user = RT::User->new($self->CurrentUser);
        $user->LoadByEmail($args{'Email'});

        unless ($user->Id) {
            $user->Load($args{'Email'});
        }
        if ($user->Id) { # If the user exists
            $principal->Load($user->PrincipalId);
        } else {

        # if the user doesn't exist, we need to create a new user
             my $new_user = RT::User->new($RT::SystemUser);

            my ( $Val, $Message ) = $new_user->Create(
                Name => $args{'Email'},
                EmailAddress => $args{'Email'},
                RealName     => $args{'Email'},
                Privileged   => 0,
                Comments     => 'Autocreated when added as a watcher');
            unless ($Val) {
                $RT::Logger->error("Failed to create user ".$args{'Email'} .": " .$Message);
                # Deal with the race condition of two account creations at once
                $new_user->LoadByEmail($args{'Email'});
            }
            $principal->Load($new_user->PrincipalId);
        }
    }
    # If we can't find this watcher, we need to bail.
    unless ($principal->Id) {
        return(0, $self->loc("Could not find or create that user"));
    }


    my $group = RT::Group->new($self->CurrentUser);
    $group->LoadQueueGroup(Type => $args{'Type'}, Queue => $self->Id);
    unless ($group->id) {
        return(0,$self->loc("Group not found"));
    }

    if ( $group->HasMember( $principal)) {

        return ( 0, $self->loc('That principal is already a [_1] for this queue', $args{'Type'}) );
    }


    my ($m_id, $m_msg) = $group->_AddMember($principal->Id);
    unless ($m_id) {
        $RT::Logger->error("Failed to add ".$principal->Id." as a member of group ".$group->Id."\n".$m_msg);

        return ( 0, $self->loc('Could not make that principal a [_1] for this queue', $args{'Type'}) );
    }
    return ( 1, $self->loc('Added principal as a [_1] for this queue', $args{'Type'}) );
}

# }}}

# {{{ sub DeleteWatcher

=head2 DeleteWatcher { Type => TYPE, PrincipalId => PRINCIPAL_ID, Email => EMAIL_ADDRESS }


Deletes a queue  watcher.  Takes two arguments:

Type  (one of Requestor,Cc,AdminCc)

and one of

PrincipalId (an RT::Principal Id of the watcher you want to remove)
    OR
Email (the email address of an existing wathcer)


=cut


sub DeleteWatcher {
    my $self = shift;

    my %args = ( Type => undef,
                 PrincipalId => undef,
                 @_ );

    unless ($args{'PrincipalId'} ) {
        return(0, $self->loc("No principal specified"));
    }
    my $principal = RT::Principal->new($self->CurrentUser);
    $principal->Load($args{'PrincipalId'});

    # If we can't find this watcher, we need to bail.
    unless ($principal->Id) {
        return(0, $self->loc("Could not find that principal"));
    }

    my $group = RT::Group->new($self->CurrentUser);
    $group->LoadQueueGroup(Type => $args{'Type'}, Queue => $self->Id);
    unless ($group->id) {
        return(0,$self->loc("Group not found"));
    }

    # {{{ Check ACLS
    #If the watcher we're trying to add is for the current user
    if ( $self->CurrentUser->PrincipalId  eq $args{'PrincipalId'}) {
        #  If it's an AdminCc and they don't have 
        #   'WatchAsAdminCc' or 'ModifyQueue', bail
  if ( $args{'Type'} eq 'AdminCc' ) {
            unless ( $self->CurrentUserHasRight('ModifyQueueWatchers')
                or $self->CurrentUserHasRight('WatchAsAdminCc') ) {
                return ( 0, $self->loc('Permission Denied'))
            }
        }

        #  If it's a Requestor or Cc and they don't have
        #   'Watch' or 'ModifyQueue', bail
        elsif ( ( $args{'Type'} eq 'Cc' ) or ( $args{'Type'} eq 'Requestor' ) ) {
            unless ( $self->CurrentUserHasRight('ModifyQueueWatchers')
                or $self->CurrentUserHasRight('Watch') ) {
                return ( 0, $self->loc('Permission Denied'))
            }
        }
        else {
            $RT::Logger->warn( "$self -> DelWatcher got passed a bogus type");
            return ( 0, $self->loc('Error in parameters to Queue->DelWatcher') );
        }
    }

    # If the watcher isn't the current user 
    # and the current user  doesn't have 'ModifyQueueWathcers' bail
    else {
        unless ( $self->CurrentUserHasRight('ModifyQueueWatchers') ) {
            return ( 0, $self->loc("Permission Denied") );
        }
    }

    # }}}


    # see if this user is already a watcher.

    unless ( $group->HasMember($principal)) {
        return ( 0,
        $self->loc('That principal is not a [_1] for this queue', $args{'Type'}) );
    }

    my ($m_id, $m_msg) = $group->_DeleteMember($principal->Id);
    unless ($m_id) {
        $RT::Logger->error("Failed to delete ".$principal->Id.
                           " as a member of group ".$group->Id."\n".$m_msg);

        return ( 0,    $self->loc('Could not remove that principal as a [_1] for this queue', $args{'Type'}) );
    }

    return ( 1, $self->loc("[_1] is no longer a [_2] for this queue.", $principal->Object->Name, $args{'Type'} ));
}

# }}}

# {{{ AdminCcAddresses

=head2 AdminCcAddresses

returns String: All queue AdminCc email addresses as a string

=cut

sub AdminCcAddresses {
    my $self = shift;
    
    unless ( $self->CurrentUserHasRight('SeeQueue') ) {
        return undef;
    }   
    
    return ( $self->AdminCc->MemberEmailAddressesAsString )
    
}   

# }}}

# {{{ CcAddresses

=head2 CcAddresses

returns String: All queue Ccs as a string of email addresses

=cut

sub CcAddresses {
    my $self = shift;

    unless ( $self->CurrentUserHasRight('SeeQueue') ) {
        return undef;
    }

    return ( $self->Cc->MemberEmailAddressesAsString);

}
# }}}


# {{{ sub Cc

=head2 Cc

Takes nothing.
Returns an RT::Group object which contains this Queue's Ccs.
If the user doesn't have "ShowQueue" permission, returns an empty group

=cut

sub Cc {
    my $self = shift;

    my $group = RT::Group->new($self->CurrentUser);
    if ( $self->CurrentUserHasRight('SeeQueue') ) {
        $group->LoadQueueGroup(Type => 'Cc', Queue => $self->Id);
    }
    return ($group);

}

# }}}

# {{{ sub AdminCc

=head2 AdminCc

Takes nothing.
Returns an RT::Group object which contains this Queue's AdminCcs.
If the user doesn't have "ShowQueue" permission, returns an empty group

=cut

sub AdminCc {
    my $self = shift;

    my $group = RT::Group->new($self->CurrentUser);
    if ( $self->CurrentUserHasRight('SeeQueue') ) {
        $group->LoadQueueGroup(Type => 'AdminCc', Queue => $self->Id);
    }
    return ($group);

}

# }}}

# {{{ IsWatcher, IsCc, IsAdminCc

# {{{ sub IsWatcher
# a generic routine to be called by IsRequestor, IsCc and IsAdminCc

=head2 IsWatcher { Type => TYPE, PrincipalId => PRINCIPAL_ID }

Takes a param hash with the attributes Type and PrincipalId

Type is one of Requestor, Cc, AdminCc and Owner

PrincipalId is an RT::Principal id 

Returns true if that principal is a member of the group Type for this queue


=cut

sub IsWatcher {
    my $self = shift;

    my %args = ( Type  => 'Cc',
        PrincipalId    => undef,
        @_
    );

    # Load the relevant group. 
    my $group = RT::Group->new($self->CurrentUser);
    $group->LoadQueueGroup(Type => $args{'Type'}, Queue => $self->id);
    # Ask if it has the member in question

    my $principal = RT::Principal->new($self->CurrentUser);
    $principal->Load($args{'PrincipalId'});

    return ($group->HasMember($principal));
}

# }}}


# {{{ sub IsCc

=head2 IsCc PRINCIPAL_ID

  Takes an RT::Principal id.
  Returns true if the principal is a requestor of the current queue.


=cut

sub IsCc {
    my $self = shift;
    my $cc   = shift;

    return ( $self->IsWatcher( Type => 'Cc', PrincipalId => $cc ) );

}

# }}}

# {{{ sub IsAdminCc

=head2 IsAdminCc PRINCIPAL_ID

  Takes an RT::Principal id.
  Returns true if the principal is a requestor of the current queue.

=cut

sub IsAdminCc {
    my $self   = shift;
    my $person = shift;

    return ( $self->IsWatcher( Type => 'AdminCc', PrincipalId => $person ) );

}

# }}}


# }}}





# }}}

# {{{ ACCESS CONTROL

# {{{ sub _Set
sub _Set {
    my $self = shift;

    unless ( $self->CurrentUserHasRight('AdminQueue') ) {
        return ( 0, $self->loc('Permission Denied') );
    }
    return ( $self->SUPER::_Set(@_) );
}

# }}}

# {{{ sub _Value

sub _Value {
    my $self = shift;

    unless ( $self->CurrentUserHasRight('SeeQueue') ) {
        return (undef);
    }

    return ( $self->__Value(@_) );
}

# }}}

# {{{ sub CurrentUserHasRight

=head2 CurrentUserHasRight

Takes one argument. A textual string with the name of the right we want to check.
Returns true if the current user has that right for this queue.
Returns undef otherwise.

=cut

sub CurrentUserHasRight {
    my $self  = shift;
    my $right = shift;

    return (
        $self->HasRight(
            Principal => $self->CurrentUser,
            Right     => "$right"
          )
    );

}

# }}}

# {{{ sub HasRight

=head2 HasRight

Takes a param hash with the fields 'Right' and 'Principal'.
Principal defaults to the current user.
Returns true if the principal has that right for this queue.
Returns undef otherwise.

=cut

# TAKES: Right and optional "Principal" which defaults to the current user
sub HasRight {
    my $self = shift;
    my %args = (
        Right     => undef,
        Principal => $self->CurrentUser,
        @_
    );
    unless ( defined $args{'Principal'} ) {
        $RT::Logger->debug("Principal undefined in Queue::HasRight");

    }
    return (
        $args{'Principal'}->HasQueueRight(
            QueueObj => $self,
            Right    => $args{'Right'}
          )
    );
}

# }}}

# }}}

1;
