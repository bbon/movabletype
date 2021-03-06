# Movable Type (r) Open Source (C) 2001-2011 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$
package MT::CMS::Theme;

use strict;
use MT::Util qw( remove_html dirify is_valid_url );
use MT::Theme;
use File::Spec;

sub list {
    my $app = shift;
    my $q   = $app->param;
    my %param;
    return $app->permission_denied()
        unless $app->can_do('open_theme_listing_screen');
    $param{screen_class} = 'settings-screen';
    my $cfg  = $app->config;
    my $blog = $app->blog;

    if ( !$blog ) {
        ## System wide screen.
        $param{website_theme_loop}
            = _build_theme_table( classes => { website => 1 } );
        $param{blog_theme_loop}
            = _build_theme_table( classes => { blog => 1 } );
        $param{both_theme_loop}
            = _build_theme_table( classes => { both => 1 } );
    }
    else {
        my $current_theme = $blog->theme;
        $param{current_theme_loop} = _build_theme_table(
            current => $current_theme,
            classes => { current => 1, },
            blog    => $blog,
        );
        if ( $blog->is_blog ) {
            $param{theme_loop} = _build_theme_table(
                current => $current_theme,
                classes => { blog => 1, both => 1 },
                blog    => $blog,
            );
        }
        else {
            $param{theme_loop} = _build_theme_table(
                current => $current_theme,
                classes => { website => 1, both => 1 },
                blog    => $blog,
            );
        }
        $param{current_theme_name} = $current_theme->label if $current_theme;
    }
    $param{nav_config}   = 1;
    $param{nav_settings} = 1;
    $param{nav_themes}   = 1;
    $param{search_label} = $app->translate('Templates');
    $param{object_type}  = 'template';

    $app->add_breadcrumb( $app->translate("Themes") );
    $param{screen_id}              = "list-themes";
    $param{screen_class}           = "theme-settings";
    $param{applied}                = $q->param('applied');
    $param{theme_uninstalled}      = $q->param('theme_uninstalled');
    $param{uninstalled_theme_name} = $q->param('uninstalled_theme_name');
    $param{warning_on_apply}       = $q->param('warning_on_apply');
    $param{refreshed}              = $q->param('refreshed');
    $app->load_tmpl( 'list_theme.tmpl', \%param );
}

sub _build_theme_table {
    my (%opts) = @_;
    my $classes = $opts{classes};
    my @data;
    my $current = $opts{current} || '';
    $current = $current->{id} if ref $current;
    my $current_theme;
    my $themes = MT::Theme->load_all_themes();
    foreach my $theme ( values %$themes ) {

        if ( $classes->{current} ) {
            next if $theme->id ne ( $current || '' );
        }
        else {
            next if !$theme->{class} || !$classes->{ $theme->{class} };
            next if $theme->id eq ( $current || '' );
        }
        my @keys = qw( id author_name author_link version );
        my %theme;
        map { $theme{$_} = $theme->{$_} } @keys;
        delete $theme{author_link} if !is_valid_url( $theme{author_link} );
        $theme{theme_id} = $theme->id;
        $theme{current} = $theme->id eq ( $current || '' ) ? 1 : 0;
        $theme{label} = ref $theme->label ? $theme->label->() : $theme->label;
        $theme{name} = $theme->name || $theme->label;
        $theme{theme_version} = $theme->version;
        $theme{theme_type}    = $theme->{type};
        $theme{protected}     = $theme->{protected};
        my ( $errors, $warnings ) = $theme->validate_versions( $opts{blog} );
        $theme{errors}        = $errors;
        $theme{warnings}      = $warnings;
        $theme{error_count}   = scalar @$errors;
        $theme{warning_count} = scalar @$warnings;
        @theme{qw(thumbnail_url thumb_w thumb_h)}
            = ( $theme->thumbnail( size => 'small' ) );
        @theme{qw(m_thumbnail_url m_thumb_w m_thumb_h)}
            = ( $theme->thumbnail( size => 'medium' ) );
        @theme{qw(l_thumbnail_url l_thumb_w l_thumb_h)}
            = ( $theme->thumbnail( size => 'large' ) );
        $theme{info}        = [ $theme->information_strings ];
        $theme{description} = $theme->description;
        $theme{blog_count}
            = MT::Blog->count( { class => '*', theme_id => $theme->id } );

        if ( $theme{current} ) {
            $current_theme = \%theme;
        }
        else {
            push @data, \%theme;
        }
    }
    @data = sort { $a->{label} cmp $b->{label} } @data;
    unshift @data, $current_theme if $current_theme;
    return \@data;
}

sub dialog_select_theme {
    my $app = shift;
    my $q   = $app->param;
    my %param;
    $param{idfield}    = $app->param('idfield');
    $param{namefield}  = $app->param('namefield');
    $param{imagefield} = $app->param('imagefield');
    return $app->permission_denied()
        unless $app->can_do('manage_themes');

    my $cfg     = $app->config;
    my $blog    = $app->blog;
    my $current = MT->config->NewUserBlogTheme;
    my $list    = _build_theme_table(
        classes => { blog => 1, both => 1, },
        current => $current
    );
    $param{theme_loop} = $list;
    $param{theme_json} = {
        map {
            $_->{theme_id} => {
                label => (
                    'CODE' eq ref $_->{label}
                    ? $_->{label}->()
                    : $_->{label}
                ),
                description => $_->{description},
                thumb       => $_->{thumbnail_url},
                thumb_w     => $_->{thumb_w},
                thumb_h     => $_->{thumb_h},
                }
            } @$list
    };
    $app->load_tmpl( 'dialog/select_theme.tmpl', \%param );
}

sub apply {
    my $app = shift;
    $app->validate_magic or return;

    return $app->permission_denied()
        unless $app->can_do('apply_theme');
    my $blog = $app->blog
        or return $app->error( MT->translate('Invalid request') );
    my $q        = $app->param;
    my $theme_id = $q->param('theme_id')
        or return $app->error( MT->translate('Invalid request') );
    require MT::Theme;
    my $theme = MT::Theme->load($theme_id)
        or return $app->error( MT->translate('Theme not found') );
    $blog->theme_id( $theme->id );
    $blog->theme_export_settings(undef);
    $blog->save;
    $blog->apply_theme;
    $app->redirect(
        $app->uri(
            mode => 'list_theme',
            args => {
                applied          => 1,
                blog_id          => $blog->id,
                warning_on_apply => $theme->{warning_on_apply},
            },
        )
    );
}

sub uninstall {
    my $app = shift;
    $app->can_do('uninstall_theme_package')
        or return $app->permission_denied();
    my $q        = $app->param;
    my $theme_id = $q->param('theme_id');
    my $theme    = MT::Theme->load($theme_id);
    if ( $theme->{type} ne 'package' ) {
        return $app->error( MT->translate('Invalid request.') );
    }
    if (   $theme->{protected}
        || !-e $theme->path
        || !-d $theme->path )
    {
        return $app->error( MT->translate('Failed to uninstall theme') );
    }
    require File::Path;
    File::Path::rmtree( $theme->path )
        or return $app->error(
        MT->translate( 'Failed to uninstall theme: [_1]', $! ) );
    my $label         = $theme->label;
    my %redirect_args = (
        theme_uninstalled      => 1,
        uninstalled_theme_name => ref($label) ? $label->() : $label,
    );
    $redirect_args{blog_id} = $app->blog->id if $app->blog;
    $app->redirect(
        $app->uri(
            mode => 'list_theme',
            args => \%redirect_args,
        )
    );
}

sub export {
    my $app = shift;
    $app->can_do('open_theme_export_screen')
        or return $app->permission_denied();
    my %param;
    my $q = $app->param;
    my $blog = $app->blog || MT->model('blog')->load( $q->param('blog_id') )
        or return $app->return_to_dashboard( redirect => 1 );
    $param{theme_class} = $blog->class;
    $param{output}      = 'themedir';
    my $hdlrs          = MT->registry('theme_element_handlers');
    my $exporters      = [];
    my $saved_settings = $blog->theme_export_settings;
    my $has_saved      = $saved_settings;
    my $last_includes  = $saved_settings->{core}{include};
    $last_includes = { map { $_ => 1 } @$last_includes };

    for my $hdlr ( keys %$hdlrs ) {
        my $exporter
            = MT->registry( theme_element_handlers => $hdlr => 'exporter' );
        next unless $exporter;
        my $tmpl      = $exporter->{template};
        my $component = $exporter->{component};
        my $cond      = $exporter->{condition};
        if ( !ref $cond ) {
            $cond = MT->handler_to_coderef($cond);
        }
        next if defined $cond && !$cond->($blog);
        push @$exporters,
            {
            id       => $hdlr,
            included => $has_saved ? $last_includes->{$hdlr} : 1,
            label =>
                MT->registry( theme_element_handlers => $hdlr => 'label' ),
            template => $tmpl,
            };
    }
    my $saved_core_values = $saved_settings->{core};
    my @save_params       = qw(
        theme_name    theme_id    theme_author_name theme_author_link
        theme_version theme_class description       include
        output
    );
    my $default_basename = [ File::Spec->splitdir( $blog->site_path ) ]->[-1]
        || dirify( $blog->name );
    my %param_default = (
        theme_name => MT->translate( 'Theme from [_1]', $blog->name ),
        theme_id   => $default_basename
        ? 'theme_from_' . $default_basename
        : 'new_theme',
        theme_author_name => '',
        theme_author_link => '',
        theme_version     => '1.0',
    );

    for my $param (@save_params) {
        my $val 
            = $saved_core_values->{$param}
            || $param_default{$param}
            || '';
        $param{$param} = ref $val ? $val->[0] : $val;
    }
    my @output_methods = (
        {   label => MT->translate('Install into themes directory'),
            id    => 'themedir',
        }
    );
    require MT::Util::Archive;
    my @arcs = MT::Util::Archive->available_formats;
    for my $arc (@arcs) {
        ## FIXME: Skip Tgz because his add_tree() doesn't work well.
        next if $arc->{key} eq 'tgz';
        push @output_methods,
            {
            label => MT->translate( 'Download [_1] archive', $arc->{label} ),
            id    => 'download.' . $arc->{key},
            };
    }
    my $all_themes = MT::Theme->load_all_themes();
    $param{existing_ids} = {
        map { $_->id => 1 }
            grep { $_->{type} ne 'package' || $_->{protected} }
            values %$all_themes
    };
    $param{output_methods}       = \@output_methods;
    $param{select_output_method} = scalar @output_methods > 1 ? 1 : 0;
    $param{exporters}            = $exporters;
    $param{save_success}         = $q->param('success');
    $param{search_label}         = $app->translate('Templates');
    $param{object_type}          = 'template';
    $app->load_tmpl( 'export_theme.tmpl', \%param );
}

sub element_dialog {
    my $app = shift;
    $app->can_do('open_theme_export_screen')
        or return $app->permission_denied();

    my $q = $app->param;
    my $blog = $app->blog || MT->model('blog')->load( $q->param('blog_id') )
        or return $app->error( MT->translate('Invalid request.') );
    my $exporter_id = $app->param('exporter_id')
        or return $app->error( $app->translate('Invalid request.') );
    my $handler = MT->registry( theme_element_handlers => $exporter_id )
        or return $app->error( $app->translate('Invalid request.') );
    my $exporter
        = MT->registry( 'theme_element_handlers', $exporter_id, 'exporter' )
        or return $app->error( $app->translate('Invalid request.') );

    my $settings = $blog->theme_export_settings || {};
    my $setting   = $settings ? $settings->{$exporter_id} : undef;
    my $code      = $exporter->{template};
    my $component = $exporter->{component};

    if ( !ref $code ) {
        $code = MT->handler_to_coderef($code);
    }
    my ( $tmpl, %element_param, $element_param );
    eval { ( $tmpl, %element_param ) = $code->( $app, $blog, $setting ); };
    if ($@) {
        MT->log(
            {   message => MT->translate(
                    'Failed to load theme export template for [_1]: [_2]',
                    $exporter_id, $@
                ),
                level    => MT::Log::WARNING(),
                class    => 'theme',
                category => 'export',
            }
        );
        next;
    }

    if ( ref $tmpl eq MT->model('template') ) {
        $element_param = $tmpl->param;
        $tmpl          = $tmpl->text;
    }
    else {
        $element_param = \%element_param;
    }
    $setting ||= {};
    my %param = (
        exporter_id => $exporter_id,
        label       => $handler->{label},
        template    => $tmpl,
        %$setting,
        %$element_param,
    );
    $app->load_tmpl( 'dialog/theme_element_detail.tmpl', \%param );
}

sub save_detail {
    my $app = shift;
    $app->can_do('do_export_theme')
        or return $app->permission_denied();
    my $q = $app->param;
    my %param;
    my $blog        = $app->blog;
    my $fmgr        = MT::FileMgr->new('Local');
    my $exporter_id = $app->param('exporter_id');
    ## Abort if theme directory is not okey for output.
    my $hdlrs = MT->registry('theme_element_handlers');
    my $settings = $blog->theme_export_settings || {};

    my $exporter = MT->registry(
        theme_element_handlers => $exporter_id => 'exporter' );
    my $setting = {};
    my $params
        = ref $exporter->{params}
        ? $exporter->{params}
        : [ $exporter->{params} ];
    for my $param (@$params) {
        $setting->{$param} = [ $app->param($param) ];
    }
    $settings->{$exporter_id} = $setting;
    $blog->theme_export_settings($settings);
    $blog->save
        or return $app->error(
        MT->translate(
            'Failed to save theme export info: [_1]',
            $blog->errstr
        )
        );
    $app->load_tmpl( 'dialog/theme_detail_saved.tmpl', \%param );
}

sub do_export {
    my $app = shift;
    $app->can_do('do_export_theme')
        or return $app->permission_denied();
    my $q    = $app->param;
    my $blog = $app->blog;
    my $theme_id 
        = dirify( $q->param('theme_id') )
        || dirify( $q->param('theme_name') )
        || 'theme_from_' . dirify( $blog->name )
        || 'theme_from_blog_' . $blog->id;
    my $theme_name    = $q->param('theme_name')    || $theme_id;
    my $theme_version = $q->param('theme_version') || '1.0';

    my $fmgr = MT::FileMgr->new('Local');

    ## $output should have 'themedir' or 'zipdownload'.
    my $output = $q->param('output') || 'themedir';

    ## Abort if theme directory is not okey for output.
    my $hdlrs       = MT->registry('theme_element_handlers');
    my $theme_dir   = MT->config('ThemesDirectory');
    my $output_path = File::Spec->catdir( $theme_dir, $theme_id );
    if ( $output eq 'themedir' && !$fmgr->can_write($theme_dir) ) {
        return $app->error(
            $app->translate(
                'Themes Directory [_1] is not writable.', $theme_dir,
            )
        );
    }

    if ( $output eq 'themedir' && $fmgr->exists($output_path) ) {
        if ( $q->param('overwrite_yes') ) {
            use File::Path 'rmtree';
            rmtree($output_path);
        }
        elsif ( $q->param('overwrite_no') ) {
            return $app->redirect(
                $app->uri(
                    mode => 'export_theme',
                    args => { blog_id => $blog->id, },
                )
            );
        }
        else {
            my %params;
            foreach ( $q->param ) {
                $params{$_} = $app->param($_);
            }

            my @include = $q->param('include');
            $params{include}      = \@include;
            $params{theme_folder} = $output_path;
            return $app->load_tmpl( 'theme_export_replace.tmpl', \%params );
        }
    }

    ## Pick up settings.
    my %includes = map { $_ => 1 } ( $q->param('include') );
    my %exporter;
    my $settings = $blog->theme_export_settings || {};
    my $elements = {};

    for my $exporter_id ( keys %$hdlrs ) {
        my $exporter
            = MT->registry(
            theme_element_handlers => $exporter_id => 'exporter' )
            or next;
        $exporter{$exporter_id} = $exporter;
        next unless $includes{$exporter_id};
    }

    ## Build data.
    my $theme_hash = {
        id    => $theme_id,
        name  => $theme_name,
        label => $theme_name,
        (   $q->param('theme_author_name')
            ? ( author_name => $q->param('theme_author_name') )
            : ()
        ),
        author_link => $q->param('theme_author_link') || '',
        version => $theme_version,
        class => ( $blog->is_blog ? 'blog' : 'website' ),
        description => $q->param('description') || '',
    };

    for my $exporter_id ( keys %$hdlrs ) {
        next unless $includes{$exporter_id};
        my $exporter = $exporter{$exporter_id};
        next unless $exporter;
        my $code = $exporter->{export};
        if ( !ref $code ) {
            $code = MT->handler_to_coderef($code);
        }
        my $setting
            = exists $settings->{$exporter_id}
            ? $settings->{$exporter_id}
            : undef;
        my $data;
        eval { $data = $code->( $app, $blog, $setting ); };
        return $app->error(
            $app->translate(
                'Error occurred during exporting [_1]: [_2]', $exporter_id,
                $@
            )
        ) if $@;
        next unless $data;
        $elements->{$exporter_id} = {
            component => $exporter->{component},
            importer  => $exporter_id,
            data      => $data,
        };
    }
    $theme_hash->{elements} = $elements;
    require File::Temp;
    my $tmproot = File::Temp::tempdir(
        DIR     => MT->config('TempDir'),
        CLEANUP => 1
    );
    my $tmpdir = File::Spec->catdir( $tmproot, $theme_id );
    $fmgr->mkpath($tmpdir);
    my $yaml_path = File::Spec->catfile( $tmpdir, 'theme.yaml' );

    for my $hdlr ( keys %$hdlrs ) {
        my $exporter
            = MT->registry( theme_element_handlers => $hdlr => 'exporter' );
        next unless $exporter;
        my $code = $exporter->{finalize};
        next unless $code;
        if ( !ref $code ) {
            $code = MT->handler_to_coderef($code);
        }
        my $finalize;
        eval {
            $finalize = $code->(
                $app, $blog, $theme_hash, $tmpdir, $settings->{$hdlr}
            );
        };
        if ($@) {
            return $app->error(
                $app->translate(
                    'Error occurred during finalizing [_1]: [_2]', $hdlr,
                    "$@",
                )
            );
        }
        if ( !defined $finalize ) {
            return $app->error(
                $app->translate(
                    'Error occurred during finalizing [_1]: [_2]', $hdlr,
                    $app->errstr,
                )
            );
        }
    }

    require MT::Util::YAML;
    $fmgr->put_data( MT::Util::YAML::Dump($theme_hash), $yaml_path )
        or return $app->error(
        $app->translate(
            'Error occurred while publishing theme: [_1]',
            $fmgr->errstr,
        )
        );

    my $printed;
    if ( $output eq 'themedir' ) {
        require File::Copy::Recursive;
        my $num = File::Copy::Recursive::dircopy( $tmpdir, $output_path );
        return $app->error(
            $app->translate(
                'Themes Directory [_1] is not writable.', $theme_dir,
            )
        ) unless $num;
    }
    elsif ( $output =~ /^download/ ) {
        my ($arctype) = $output =~ /\.(.*)$/;
        my $arc_info = MT->registry( archivers => $arctype )
            or die "Unknown archiver type : $arctype";
        require MT::Util::Archive;
        my $arcfile = File::Temp::tempnam( $tmproot, $theme_id );
        my $arc = MT::Util::Archive->new( $arctype, $arcfile )
            or die "Can't load archiver : " . MT::Util::Archive->errstr;
        $arc->add_tree($tmproot);
        $arc->close;
        my $newfilename = $theme_id;
        $newfilename .= $theme_version if $theme_version;
        $newfilename .= '.' . $arc_info->{extension};
        open my $fh, "<", $arcfile;
        binmode $fh;
        $app->{no_print_body} = 1;
        $app->set_header(
            "Content-Disposition" => "attachment; filename=$newfilename" );
        $app->send_http_header( $arc_info->{mimetype} );
        my $data;

        while ( read $fh, my ($chunk), 8192 ) {
            $data .= $chunk;
        }
        close $fh;
        $app->print($data);
        $printed = 1;
    }

    my @core_params = qw(
        theme_name    theme_id    theme_author_name theme_author_link
        theme_version theme_class description       include
        output
    );
    for my $param (@core_params) {
        $settings->{core}{$param} = [ $q->param($param) ];
    }
    $blog->theme_export_settings($settings);
    $blog->save
        or return $app->error(
        MT->translate(
            'Failed to save theme export info: [_1]',
            $blog->errstr
        )
        );
    ## if finished with no errors, should return to theme export screen again.
    return if $printed;
    $app->redirect(
        $app->uri(
            mode => 'export_theme',
            args => {
                success => 1,
                blog_id => $blog->id,
            },
        )
    );
}

1;
