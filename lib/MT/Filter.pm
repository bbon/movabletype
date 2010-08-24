# Movable Type (r) Open Source (C) 2001-2010 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

package MT::Filter;
use strict;
use warnings;
use MT::Serialize;

use base qw( MT::Object );

__PACKAGE__->install_properties(
    {   column_defs => {
            'id'        => 'integer not null auto_increment',
            'author_id' => 'integer not null',
            'blog_id'   => 'integer not null',
            'label'     => 'string(255)',
            'object_ds' => 'string(255)',
            'items'     => 'blob',
        },
        datasource  => 'filter',
        primary_key => 'id',
        audit       => 1,
    }
);

sub class_label {
    MT->translate("Filter");
}

sub class_label_plural {
    MT->translate("Filters");
}

{
    my $ser;

    sub items {
        my $self = shift;
        $ser
            ||= MT::Serialize->new('MT'); # force MT serialization for plugins
        if (@_) {
            my $filter = shift;
            if ( ref($filter) ) {
                $self->column( 'items', $ser->serialize( \$filter ) );
            }
            else {
                $self->column( 'items', $filter );
            }
            $filter;
        }
        else {
            my $filter = $self->column('items');
            return undef unless defined $filter;
            my $thawed = $ser->unserialize($filter);
            my $ret = defined $thawed ? $$thawed : undef;
            return $ret;
        }
    }
}

sub append_item {
    my $self  = shift;
    my $item  = shift;
    my $items = $self->items || [];
    push @$items, $item;
    $self->items($items);
}

sub to_hash {
    my $self = shift;
    return {
        id         => $self->id,
        label      => $self->label,
        items      => $self->items,
        can_edit   => 1,
        can_save   => 1,
        can_delete => 1,
    };
}

sub load_objects {
    my $self = shift;
    my (%options) = @_;
    my ( $blog_id, $parent_id, $sort, $dir, $limit, $offset )
        = @options{ 'blog_id', 'parent_id', 'sort_by', 'sort_order', 'limit',
        'offset' };
    my $ds       = $self->object_ds;
    my $setting  = MT->registry( listing_screens => $ds ) || {};
    my $obj_type = $setting->{object_type} || $ds;
    my $class    = MT->model($obj_type);
    my $items    = $self->items;
    my $terms
        = $class->can('list_default_terms') ? $class->list_default_terms : {};
    $terms->{blog_id}   = $blog_id   if $blog_id;
    $terms->{parent_id} = $parent_id if $parent_id;
    my $args = {};
    my @items;
    require MT::ListProperty;

    for my $item (@$items) {
        my $id = $item->{type};
        my $prop = MT::ListProperty->instance( $ds, $id )
            or die "Invalid Filter $id";
        $item->{prop} = $prop;
        push @items, $item;
    }
    @items = sort {
        ( $a->{prop}->priority || 5 ) <=> ( $b->{prop}->priority || 5 )
    } @items;
    my @grep_items = grep { $_->{prop}->has('grep') } @items;

    ## Prepare terms
    my @additional_terms;
    for my $item (@items) {
        my $prop = $item->{prop};
        $prop->has('terms') or next;
        my $filter_terms = $prop->terms( $item->{args}, $terms, $args );
        if ($filter_terms) {
            push @additional_terms, ( '-and', $filter_terms );
        }
    }
    if ( scalar @additional_terms ) {
        if ( !scalar %$terms ) {
            shift @additional_terms;
            $terms = [@additional_terms];
        }
        else {
            $terms = [ $terms, @additional_terms ];
        }
    }

    my $sort_prop;
    $sort_prop = MT::ListProperty->instance( $ds, $sort ) if $sort;
    if ( $sort_prop && $sort_prop->has('sort') ) {
        $args->{direction}
            = ( $dir && $dir eq 'descend' ) ? 'descend' : 'ascend';
        $sort_prop->sort( $terms, $args );
    }

    if (!( scalar @grep_items )
        && (!$sort_prop
            || (   !( $sort_prop->has('sort_method') )
                && !( $sort_prop->has('bulk_sort') ) )
        )
        )
    {
        $args->{limit}  = $limit;
        $args->{offset} = $offset;
    }

    ## It's time to load now.
    my @objs = $class->load( $terms, $args );

    for my $item (@grep_items) {
        @objs = grep { $item->{prop}->grep( $item->{args}, $_ ) } @objs;
    }

    if ( $sort_prop && $sort_prop->has('bulk_sort') ) {
        @objs = $sort_prop->bulk_sort( \@objs );
        @objs = reverse @objs
            if ( $dir && $dir eq 'descend' );
    }
    elsif ( $sort_prop && $sort_prop->has('sort_method') ) {
        @objs = sort { $sort_prop->sort_method( $a, $b ) } @objs;
        @objs = reverse @objs
            if ( $dir && $dir eq 'descend' );
    }

    if ((   scalar @grep_items
            || ($sort_prop
                && (   $sort_prop->has('sort_method')
                    || $sort_prop->has('bulk_sort') )
            )
        )
        && $limit
        && $limit < scalar @objs
        )
    {
        @objs = @objs[ $offset .. $limit + $offset - 1 ];
    }

    return @objs;
}

sub count_objects {
    my $self      = shift;
    my (%options) = @_;
    my $blog_id   = $options{blog_id};
    my $ds        = $self->object_ds;
    my $setting   = MT->registry( listing_screens => $ds ) || {};
    my $obj_type  = $setting->{object_type} || $ds;
    my $class     = MT->model($obj_type);
    my $items     = $self->items;
    my $terms
        = $class->can('list_default_terms') ? $class->list_default_terms : {};
    $terms->{blog_id} = $blog_id if $blog_id;
    my $args = {};
    require MT::ListProperty;
    my @items;

    for my $item (@$items) {
        my $id = $item->{type};
        my $prop = MT::ListProperty->instance( $ds, $id )
            or die "Invalid Filter $id";
        $item->{prop} = $prop;
        push @items, $item;
    }
    @items = sort {
        ( $a->{prop}->priority || 5 ) <=> ( $b->{prop}->priority || 5 )
    } @items;
    my @grep_items = grep { $_->{prop}->has('grep') } @items;

    ## Prepare terms
    my @additional_terms;
    for my $item (@items) {
        my $prop         = $item->{prop};
        my $code         = $prop->has('terms') or next;
        my $filter_terms = $prop->terms( $item->{args}, $terms, $args );
        if ($filter_terms) {
            push @additional_terms, ( '-and', $filter_terms );
        }
    }
    if ( scalar @additional_terms ) {
        if ( !scalar %$terms ) {
            shift @additional_terms;
            $terms = \@additional_terms;
        }
        else {
            $terms = [ $terms, @additional_terms ];
        }
    }
    if ( !( scalar @grep_items ) ) {
        return $class->count( $terms, $args );
    }

    my @objs = $class->load( $terms, $args );

    for my $item (@items) {
        my $coderef = $item->{prop}->has('grep') or next;
        @objs = grep { $item->{prop}->grep( $item->{args}, $_ ) } @objs;
    }
    return scalar @objs;
}

sub pack_terms {
    my $prop = shift;
    my ( $args, $load_terms, $load_args ) = @_;
    my $op = $prop->{item}{op} || 'and';
    $op = '-' . $op;
    my $items = $prop->{item}{items};
    my $ds    = $prop->{datasource};
    my @items;
    require MT::ListProperty;

    for my $item (@$items) {
        my $id = delete $item->{type};
        my $list_prop = MT::ListProperty->instance( $ds, $id )
            or die "Invalid Filter $id";
        $item->{prop} = $list_prop;
        push @items, $item;
    }

    @items = sort {
        ( $a->{prop}->priority || 5 ) <=> ( $b->{prop}->priority || 5 )
    } @items;
    my @terms;
    for my $item (@items) {
        my $prop = $item->{prop};
        $prop->has('terms') or next;
        my $filter_terms
            = $prop->terms( $item->{args}, $load_terms, $load_args );
        push @terms, $filter_terms if $filter_terms;
    }
    unshift @terms, $op;
    return \@terms;
}

sub pack_grep {

    # TBD
    1;
}

1;
