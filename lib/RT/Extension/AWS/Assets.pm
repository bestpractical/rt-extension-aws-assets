use strict;
use warnings;
package RT::Extension::AWS::Assets;

use Paws;
use Paws::Credential::Explicit;

use Data::Printer;

our $VERSION = '0.01';

=head1 NAME

RT-Extension-AWS-Assets - Manage AWS resources in RT assets

=head1 DESCRIPTION

Manage AWS resources in RT assets

=head1 RT VERSION

Works with RT 5.0

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item Edit your F</opt/rt4/etc/RT_SiteConfig.pm>

Add this line:

    Plugin('RT::Extension::AWS::Assets');

=item Clear your mason cache

    rm -rf /opt/rt5/var/mason_data/obj

=item Restart your webserver

=back

=head1 METHODS

=cut

sub ReloadFromAWS {
    my $asset = shift;

    my $res_obj = FetchSingleAssetFromAWS(
                      AWSID => $asset->FirstCustomFieldValue('AWS ID'),
                      ServiceType => $asset->FirstCustomFieldValue('Service Type'),
                      Region => $asset->FirstCustomFieldValue('Region'));

    UpdateAWSAsset($asset, $res_obj);
}


sub AWSCredentials {
    my $credentials = Paws::Credential::Explicit->new(
        access_key => RT->Config->Get('AWS_ACCESS_KEY'),
        secret_key => RT->Config->Get('AWS_SECRET_KEY'),
    );
    return $credentials;
}

sub FetchSingleAssetFromAWS {
    my %args = @_;

    unless ( $args{'AWSID'} ) {
        RT->Logger->error('RT-Extension-AWS-Assets: No AWS ID found.');
        return;
    }

    unless ( $args{'ServiceType'}) {
        RT->Logger->error('RT-Extension-AWS-Assets: No Service Type found.');
        return;
    }

    my $instance_obj;
    my $credentials = AWSCredentials();

    eval {
        my $service = Paws->service($args{'ServiceType'}, credentials => $credentials, region => $args{'Region'});
        my $res = $service->DescribeInstances(InstanceIds => [$args{'AWSID'}]);
        $instance_obj = $res->Reservations->[0]->Instances->[0];
    };

    if ( $@ ) {
        RT->Logger->error("RT-Extension-AWS-Assets: Failed call to AWS: " . $@);
    }

    return $instance_obj;
}

sub FetchMultipleAssetsFromAWS {
    my %args = (
        MaxResults => 5,
        @_,
    );

    unless ( $args{'Region'} ) {
        RT->Logger->error('RT-Extension-AWS-Assets: No Region found.');
        return;
    }

    unless ( $args{'ServiceType'}) {
        RT->Logger->error('RT-Extension-AWS-Assets: No Service Type found.');
        return;
    }

    my $reservations;
    my $credentials = AWSCredentials();
    my $res;

    eval {
        my $service = Paws->service($args{'ServiceType'}, credentials => $credentials, region => $args{'Region'});

        if ( $args{'NextToken'} ) {
            $res = $service->DescribeInstances(MaxResults => $args{'MaxResults'}, NextToken => $args{'NextToken'});
        }
        else {
            $res = $service->DescribeInstances(MaxResults => $args{'MaxResults'});
        }

        $reservations = $res->Reservations;
    };

    if ( $@ ) {
        RT->Logger->error("RT-Extension-AWS-Assets: Failed call to AWS: " . $@);
    }

    return ($reservations, $res->NextToken);
}

=pod

Accept a loaded RT::Asset object and a Paws Instance object.

=cut

sub UpdateAWSAsset {
    my $asset = shift;
    my $paws_obj = shift;

    foreach my $aws_value ( @{ RT->Config->Get('AWSAssetsUpdateFields') } ) {

        my $submethod;
        my $cf_name = $aws_value;
        ($submethod, $cf_name) = split(':', $aws_value) if $aws_value =~ /:/;

        my $method = $cf_name;
        $method =~ s/\s+//g;

        my ($ret, $msg);

        if ( $submethod && $submethod eq 'Tags' ) {
            foreach my $tag ( @{ $paws_obj->Tags } ) {
                if ( $tag->Key eq $cf_name ) {
                    if ( $cf_name eq 'Name' ) {
                        # Name isn't a CF but a core asset field
                        ($ret, $msg) = $asset->SetName($tag->Value);

                        if ( $msg && $msg =~ /That is already the current value/ ) {
                            # Don't log an error for the "current value" message
                            $ret = 1;
                        }
                        last;
                    }
                    else {
                        ($ret, $msg) = $asset->AddCustomFieldValue( Field => $cf_name, Value => $tag->Value );
                        last;
                    }
                }
            }
        }
        elsif ( $submethod ) {
            ($ret, $msg) = $asset->AddCustomFieldValue( Field => $cf_name, Value => $paws_obj->$submethod->$method );
        }
        elsif ( $cf_name eq 'Platform' ) {
            # Paws currently defaults Platform to Windows. All of our systems are
            # currently "Linux/UNIX" so set that.
            ($ret, $msg) = $asset->AddCustomFieldValue( Field => $cf_name, Value => "Linux/UNIX" );
        }
        else {
            ($ret, $msg) = $asset->AddCustomFieldValue( Field => $cf_name, Value => $paws_obj->$method );
        }

        unless ( $ret ) {
            RT->Logger->error("RT-Extension-AWS-Assets: unable to update CF $cf_name: $msg");
        }
    }

    return;
}

sub InsertAWSAssets {
    my %args = (
        @_
    );

    my $catalog = RT->Config->Get('AWSAssetsInstanceCatalog');

    for my $reservation ( @{ $args{'Reservations'} } ) {
        my $instance = $reservation->Instances->[0];

        # Load as system user to find all possible assets to avoid
        # trying to create a duplicate CurrentUser might not be able to see
        my $assets = RT::Assets->new( RT->SystemUser );
        my ($ok, $msg) = $assets->FromSQL("Catalog = '" . $catalog .
            "' AND 'CF.{AWS ID}' = '" . $instance->InstanceId . "'");

        # AWS ID is unique, so there should only ever be 1 or 0
        my $asset = $assets->First;

        # Search for an existing asset, next if found
        # Asset already exists, next
        RT->Logger->debug("Asset for " . $instance->InstanceId . " exists, skipping")
            if $asset and $asset->Id;
        next if $asset and $asset->Id;

        # Try to create a new asset with AWS ID, Region, Service Type
        my $new_asset = RT::Asset->new($args{'CurrentUser'});

        my $aws_id_cf = LoadCustomFieldByIdentifier($new_asset, 'AWS ID', $catalog, $args{'CurrentUser'});
        unless ( $aws_id_cf && $aws_id_cf->Id ) {
            RT->Logger->error('Unable to load AWS ID CF for asset');
            next;
        }

        my $region_cf = LoadCustomFieldByIdentifier($new_asset, 'Region', $catalog, $args{'CurrentUser'});
        unless ( $region_cf && $region_cf->Id ) {
            RT->Logger->error('Unable to load Region CF for asset');
            next;
        }

        my $service_type_cf = LoadCustomFieldByIdentifier($new_asset, 'Service Type', $catalog, $args{'CurrentUser'});
        unless ( $service_type_cf && $service_type_cf->Id ) {
            RT->Logger->error('Unable to load Service Type CF for asset');
            next;
        }

        ($ok, $msg) = $new_asset->Create(
            Catalog => RT->Config->Get('AWSAssetsInstanceCatalog'),
            'CustomField-' . $aws_id_cf->Id => $instance->InstanceId,
            'CustomField-' . $region_cf->Id => $args{'Region'},
            'CustomField-' . $service_type_cf->Id => $args{'ServiceType'},
        );

        if ( not $ok ) {
            RT->Logger->error('Unable to create new asset for instance ' . $instance->InstanceId . ' ' . $msg);
            next;
        }
        else {
            RT->Logger->debug('Created asset ' . $new_asset->Id . ' for instance ' . $instance->InstanceId);
        }

        # Call UpdateAWSAsset to load remaining CFs
        UpdateAWSAsset($new_asset, $instance);
    }
    return;
}

sub UpdateAWSAssets {
    my %args = (
        @_
    );

    my $catalog = RT->Config->Get('AWSAssetsInstanceCatalog');

    for my $reservation ( @{ $args{'Reservations'} } ) {
        my $instance = $reservation->Instances->[0];

        # Load as system user to find all possible assets to avoid
        # trying to create a duplicate CurrentUser might not be able to see
        my $assets = RT::Assets->new( RT->SystemUser );
        my ($ok, $msg) = $assets->FromSQL("Catalog = '" . $catalog .
            "' AND 'CF.{AWS ID}' = '" . $instance->InstanceId . "'");

        # AWS ID is unique, so there should only ever be 1 or 0
        my $asset = $assets->First;

        unless ( $asset and $asset->Id ) {
            RT->Logger->debug("No asset found for " . $instance->InstanceId . ", skipping");
            next;
        }

        UpdateAWSAsset($asset, $instance);
        RT->Logger->debug('Updated asset ' . $asset->Id . ' ' . $asset->Name);
    }
    return;
}

# We don't have a catalog in the empty asset object when we want to
# load the CFs, so create a custom version of the loader that accepts
# catalog as a parameter.

sub LoadCustomFieldByIdentifier {
    my $asset = shift;
    my $field = shift;
    my $catalog = shift;
    my $current_user = shift;

    my $cf = RT::CustomField->new( $current_user );
    $cf->SetContextObject( $asset );
    my ($ok, $msg) = $cf->LoadByNameAndCatalog( Name => $field, Catalog => $catalog );
    return $cf;
}

=head1 AUTHOR

=for html <p>All bugs should be reported via email to <a
href="mailto:bug-RT-Extension-AWS-Assets@rt.cpan.org">bug-RT-Extension-AWS-Assets@rt.cpan.org</a>
or via the web at <a
href="http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-AWS-Assets">rt.cpan.org</a>.</p>

=for text
    All bugs should be reported via email to
        bug-RT-Extension-AWS-Assets@rt.cpan.org
    or via the web at
        http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-AWS-Assets

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2024 by Best Practical Solutions, LLC

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
