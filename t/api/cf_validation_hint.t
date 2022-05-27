use strict;
use warnings;

use RT::Test tests => 6;

my $cf = RT::CustomField->new($RT::SystemUser);
my ( $id, $ret, $msg );

diag "single select";
( $id, $msg ) = $cf->Create(
    Name      => 'single_select',
    Type      => 'FreeformSingle',
    MaxValues => '1',
    Queue     => 0,
);
ok( $id, $msg );

is( $cf->FriendlyPattern, '', 'Empty hint with no pattern' );

( $ret, $msg ) = $cf->SetPattern( '^(?#CustomPattern).*$' );

is( $cf->FriendlyPattern, 'Input must match [CustomPattern]', 'Hint from pattern comment' );

( $ret, $msg ) = $cf->SetValidationHint( 'CustomHint' );

is( $cf->FriendlyPattern, 'Input must match CustomHint', 'Explicit hint overrides pattern comment' );

( $ret, $msg ) = $cf->SetValidationHint( '' );

( $ret, $msg ) = $cf->SetPattern( '^.*$' );

is( $cf->FriendlyPattern, 'Input must match ^.*$', 'Hint from pattern' );

( $ret, $msg ) = $cf->SetValidationHint( 'CustomHint' );

is( $cf->FriendlyPattern, 'Input must match CustomHint', 'Explicit hint overrides pattern text' );

