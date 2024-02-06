use strict;
use warnings;
package RT::Extension::AWS::Assets;

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
