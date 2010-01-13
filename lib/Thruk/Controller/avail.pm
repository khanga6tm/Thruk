package Thruk::Controller::avail;

use strict;
use warnings;
use parent 'Catalyst::Controller';

=head1 NAME

Thruk::Controller::avail - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

##########################################################
sub index :Path :Args(0) :MyAction('AddDefaults') {
    my ( $self, $c ) = @_;

    # set defaults
    $c->stash->{title}            = 'Availability';
    $c->stash->{infoBoxTitle}     = 'Availability Report';
    $c->stash->{page}             = 'avail';
    $c->stash->{'no_auto_reload'} = 1;

    # lookup parameters
    my $report_type    = $c->{'request'}->{'parameters'}->{'report_type'};
    my $get_date_parts = $c->{'request'}->{'parameters'}->{'get_date_parts'};
    my $host           = $c->{'request'}->{'parameters'}->{'host'};
    my $hostgroup      = $c->{'request'}->{'parameters'}->{'hostgroup'};
    my $service        = $c->{'request'}->{'parameters'}->{'service'};
    my $servicegroup   = $c->{'request'}->{'parameters'}->{'servicegroup'};
    my $timeperiod     = $c->{'request'}->{'parameters'}->{'timeperiod'};


    # set them for our template
    $c->stash->{report_type}  = $report_type;
    $c->stash->{host}         = $host;
    $c->stash->{hostgroup}    = $hostgroup;
    $c->stash->{service}      = $service;
    $c->stash->{servicegroup} = $servicegroup;

    # set infobox title
    if(defined $report_type) {
        if($report_type eq 'hosts') {
            $c->stash->{infoBoxTitle} = 'Host Availability Report';
        }
        if($report_type eq 'hostgroups') {
            $c->stash->{infoBoxTitle} = 'Hostgroup Availability Report';
        }
        if($report_type eq 'servicegroups') {
            $c->stash->{infoBoxTitle} = 'Servicegroup Availability Report';
        }
        if($report_type eq 'services') {
            $c->stash->{infoBoxTitle} = 'Service Availability Report';
        }
    }

    # Step 1 - select report type
    if(!defined $timeperiod and !defined $get_date_parts and !defined $report_type and $self->_show_step_1($c)){
    }

    # Step 2 - select specific host/service/group
    if(!defined $timeperiod and !defined $get_date_parts and defined $report_type and $self->_show_step_2($c)) {
    }

    # Step 3 - select date parts
    elsif(!defined $timeperiod and defined $get_date_parts and  $self->_show_step_3($c)) {
    }

    # Step 4 - create report
    elsif(defined $timeperiod
          and (defined $host or defined $service or defined $servicegroup or defined $hostgroup)
          and $self->_create_report($c)) {
    }

    # Fallback
    else {
        $self->_show_step_1($c);
    }
}

##########################################################
sub _show_step_1 {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'avail_step_1.tt';
    return 1;
}


##########################################################
sub _show_step_2 {
    my ( $self, $c ) = @_;
    my $report_type = $c->{'request'}->{'parameters'}->{'report_type'};

    my $data;
    if($report_type eq 'hosts') {
        $data = $c->{'live'}->selectall_hashref("GET hosts\nColumns: name".Thruk::Helper::get_auth_filter($c, 'hosts'), 'name');
    }
    if($report_type eq 'hostgroups') {
        $data = $c->{'live'}->selectall_hashref("GET hostgroups\nColumns: name".Thruk::Helper::get_auth_filter($c, 'hostgroups'), 'name');
    }
    if($report_type eq 'servicegroups') {
        $data = $c->{'live'}->selectall_hashref("GET servicegroups\nColumns: name".Thruk::Helper::get_auth_filter($c, 'servicegroups'), 'name');
    }
    if($report_type eq 'services') {
        my $services = $c->{'live'}->selectall_arrayref("GET services\n".Thruk::Helper::get_auth_filter($c, 'services')."\nColumns: host_name description", { Slice => 1});
        for my $service (@{$services}) {
            $data->{$service->{'host_name'}.";".$service->{'description'}} = 1;
        }
    }

    if(defined $data) {
        my @sorted = sort keys %{$data};
        $c->stash->{data}        = \@sorted;
        $c->stash->{template}    = 'avail_step_2.tt';
        return 1;
    }

    return 0;
}

##########################################################
sub _show_step_3 {
    my ( $self, $c ) = @_;

    $c->stash->{timeperiods} = $c->{'live'}->selectall_arrayref("GET timeperiods\nColumns: name".Thruk::Helper::get_auth_filter($c, 'timeperiods'), { Slice => 1});
    $c->stash->{template}    = 'avail_step_3.tt';

    return 1;
}

##########################################################
sub _create_report {
    my ( $self, $c ) = @_;
    my $start_time   = time();

    my $host           = $c->{'request'}->{'parameters'}->{'host'};
    my $hostgroup      = $c->{'request'}->{'parameters'}->{'hostgroup'};
    my $service        = $c->{'request'}->{'parameters'}->{'service'};
    my $servicegroup   = $c->{'request'}->{'parameters'}->{'servicegroup'};

    if(defined $host and $host eq 'null') { undef $host; }

    if(defined $host and $host ne 'all') {
        $c->stash->{template}   = 'avail_report_host.tt';
    }
    elsif(defined $host and $host eq 'all') {
        $c->stash->{template}   = 'avail_report_hosts.tt';
    }
    elsif(defined $hostgroup and $hostgroup ne '') {
        $c->stash->{template}   = 'avail_report_hostgroup.tt';
    }
    elsif(defined $service and $service ne 'all') {
        $c->stash->{template}   = 'avail_report_service.tt';
    }
    elsif(defined $service and $service eq 'all') {
        $c->stash->{template}   = 'avail_report_services.tt';
    }
    elsif(defined $servicegroup and $servicegroup ne '') {
        $c->stash->{template}   = 'avail_report_servicegroup.tt';
    } else {
        return;
    }

    # get timeperiod
    my $timeperiod                      = $c->{'request'}->{'parameters'}->{'timeperiod'};
    my $smon                            = $c->{'request'}->{'parameters'}->{'smon'};
    my $sday                            = $c->{'request'}->{'parameters'}->{'sday'};
    my $syear                           = $c->{'request'}->{'parameters'}->{'syear'};
    my $shour                           = $c->{'request'}->{'parameters'}->{'shour'};
    my $smin                            = $c->{'request'}->{'parameters'}->{'smin'};
    my $ssec                            = $c->{'request'}->{'parameters'}->{'ssec'};
    my $emon                            = $c->{'request'}->{'parameters'}->{'emon'};
    my $eday                            = $c->{'request'}->{'parameters'}->{'eday'};
    my $eyear                           = $c->{'request'}->{'parameters'}->{'eyear'};
    my $ehour                           = $c->{'request'}->{'parameters'}->{'ehour'};
    my $emin                            = $c->{'request'}->{'parameters'}->{'emin'};
    my $esec                            = $c->{'request'}->{'parameters'}->{'esec'};
    my $t1                              = $c->{'request'}->{'parameters'}->{'t1'};
    my $t2                              = $c->{'request'}->{'parameters'}->{'t2'};

    my($start,$end) = Thruk::Helper->_get_start_end_for_timeperiod($timeperiod,$smon,$sday,$syear,$shour,$smin,$ssec,$emon,$eday,$eyear,$ehour,$emin,$esec,$t1,$t2);

    $c->log->debug("start: ".$start." - ".(scalar localtime($start)));
    $c->log->debug("end  : ".$end." - ".(scalar localtime($end)));
    return 0 if (!defined $start or !defined $end);

    $c->stash->{start}      = $start;
    $c->stash->{end}        = $end;
    $c->stash->{timeperiod} = $timeperiod;

    my $rpttimeperiod                = $c->{'request'}->{'parameters'}->{'rpttimeperiod'};
    my $assumeinitialstates          = $c->{'request'}->{'parameters'}->{'assumeinitialstates'};
    my $assumestateretention         = $c->{'request'}->{'parameters'}->{'assumestateretention'};
    my $assumestatesduringnotrunning = $c->{'request'}->{'parameters'}->{'assumestatesduringnotrunning'};
    my $includesoftstates            = $c->{'request'}->{'parameters'}->{'includesoftstates'};
    my $initialassumedhoststate      = $c->{'request'}->{'parameters'}->{'initialassumedhoststate'};
    my $initialassumedservicestate   = $c->{'request'}->{'parameters'}->{'initialassumedservicestate'};
    my $backtrack                    = $c->{'request'}->{'parameters'}->{'backtrack'};
    my $show_log_entries             = $c->{'request'}->{'parameters'}->{'show_log_entries'};

    $c->stash->{rpttimeperiod}                = $rpttimeperiod;
    $c->stash->{assumeinitialstates}          = $assumeinitialstates;
    $c->stash->{assumestateretention}         = $assumestateretention;
    $c->stash->{assumestatesduringnotrunning} = $assumestatesduringnotrunning;
    $c->stash->{includesoftstates}            = $includesoftstates;
    $c->stash->{initialassumedhoststate}      = $initialassumedhoststate;
    $c->stash->{initialassumedservicestate}   = $initialassumedservicestate;
    $c->stash->{backtrack}                    = $backtrack;
    $c->stash->{show_log_entries}             = $show_log_entries;

    # get groups / hosts /services
    my $groupfilter = "";
    my $hostfilter  = "";

    # a single host
    if(defined $host and $host ne 'all') {
        return unless $c->check_permissions('host', $host);
    }

    # all hosts
    elsif(defined $host and $host eq 'all') {
        my $host_data = $c->{'live'}->selectall_hashref("GET hosts\n".Thruk::Helper::get_auth_filter($c, 'hosts')."\nColumns: name", 'name' );
        $c->stash->{'hosts'} = $host_data;
    }

    # one or all hostgroups
    elsif(defined $hostgroup and $hostgroup ne '') {
        if($hostgroup ne '' and $hostgroup ne 'all') {
            $groupfilter = "Filter: name = $hostgroup\n";
            $hostfilter  = "Filter: groups >= $hostgroup\n";
        }
        my $host_data = $c->{'live'}->selectall_hashref("GET hosts\n".Thruk::Helper::get_auth_filter($c, 'hosts')."\nColumns: name\n$hostfilter", 'name' );
        my $groups    = $c->{'live'}->selectall_arrayref("GET hostgroups\n".Thruk::Helper::get_auth_filter($c, 'hostgroups')."\n$groupfilter\nColumns: name members", { Slice => {} });

        # join our groups together
        my %joined_groups;
        for my $group (@{$groups}) {
            my $name = $group->{'name'};
            if(!defined $joined_groups{$name}) {
                $joined_groups{$name}->{'name'}  = $group->{'name'};
                $joined_groups{$name}->{'hosts'} = {};
            }

            for my $hostname (split /,/, $group->{'members'}) {
                # show only hosts with proper authorization
                next unless defined $host_data->{$hostname};

                if(!defined $joined_groups{$name}->{'hosts'}->{$hostname}) {
                    $joined_groups{$name}->{'hosts'}->{$hostname} = 1;
                }
            }
            # remove empty groups
            if(scalar keys %{$joined_groups{$name}->{'hosts'}} == 0) {
                delete $joined_groups{$name};
            }
        }
        $c->stash->{'groups'} = \%joined_groups;
    }

    # a single service
    elsif(defined $service and $service ne 'all') {
        ($host,$service) = split/;/,$service;
        return unless $c->check_permissions('service', $service, $host);
        $c->stash->{host}    = $host;
        $c->stash->{service} = $service;
    }

    # all services
    elsif(defined $service and $service eq 'all') {
        my $services = $c->{'live'}->selectall_arrayref("GET services\n".Thruk::Helper::get_auth_filter($c, 'services')."\nColumns: host_name description", { Slice => 1});
        my $services_data;
        for my $service (@{$services}) {
            $services_data->{$service->{'host_name'}.";".$service->{'description'}} = {
                'host_name'   => $service->{'host_name'},
                'description' => $service->{'description'},
            };
        }
        $c->stash->{'services'} = $services_data;
    }

    # one or all servicegroups
    elsif(defined $servicegroup and $servicegroup ne '') {
    }

    # finished
    $c->stash->{time_token} = time() - $start_time;

    return 1;
}

=head1 AUTHOR

Sven Nierlein, 2009, <nierlein@cpan.org>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
