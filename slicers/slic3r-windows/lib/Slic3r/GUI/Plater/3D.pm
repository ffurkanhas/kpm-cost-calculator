package Slic3r::GUI::Plater::3D;
use strict;
use warnings;
use utf8;

use List::Util qw();
use Wx qw(:misc :pen :brush :sizer :font :cursor :keycode wxTAB_TRAVERSAL);
use Wx::Event qw(EVT_KEY_DOWN EVT_CHAR);
use base qw(Slic3r::GUI::3DScene Class::Accessor);

__PACKAGE__->mk_accessors(qw(
    on_rotate_object_left on_rotate_object_right on_scale_object_uniformly
    on_remove_object on_increase_objects on_decrease_objects));

sub new {
    my $class = shift;
    my ($parent, $objects, $model, $print, $config) = @_;
    
    my $self = $class->SUPER::new($parent);
    $self->enable_picking(1);
    $self->enable_moving(1);
    $self->select_by('object');
    $self->drag_by('instance');
    
    $self->{objects}            = $objects;
    $self->{model}              = $model;
    $self->{print}              = $print;
    $self->{config}             = $config;
    $self->{on_select_object}   = sub {};
    $self->{on_instances_moved} = sub {};
    $self->{on_wipe_tower_moved} = sub {};
    
    $self->on_select(sub {
        my ($volume_idx) = @_;
        $self->{on_select_object}->(($volume_idx == -1) ? undef : $self->volumes->[$volume_idx]->object_idx)
            if ($self->{on_select_object});
    });
    $self->on_move(sub {
        my @volume_idxs = @_;
        
        my %done = ();  # prevent moving instances twice
        my $object_moved;
        my $wipe_tower_moved;
        foreach my $volume_idx (@volume_idxs) {
            my $volume = $self->volumes->[$volume_idx];
            my $obj_idx = $volume->object_idx;
            my $instance_idx = $volume->instance_idx;
            next if $done{"${obj_idx}_${instance_idx}"};
            $done{"${obj_idx}_${instance_idx}"} = 1;
            if ($obj_idx < 1000) {
                # Move a regular object.
                my $model_object = $self->{model}->get_object($obj_idx);
                $model_object
                    ->instances->[$instance_idx]
                    ->offset
                    ->translate($volume->origin->x, $volume->origin->y); #))
                $model_object->invalidate_bounding_box;
                $object_moved = 1;
            } elsif ($obj_idx == 1000) {
                # Move a wipe tower proxy.
                $wipe_tower_moved = $volume->origin;
            }
        }
        
        $self->{on_instances_moved}->()
            if $object_moved && $self->{on_instances_moved};
        $self->{on_wipe_tower_moved}->($wipe_tower_moved)
            if $wipe_tower_moved && $self->{on_wipe_tower_moved};
    });

    EVT_KEY_DOWN($self, sub {
        my ($s, $event) = @_;
        if ($event->HasModifiers) {
            $event->Skip;
        } else {
            my $key = $event->GetKeyCode;
            if ($key == WXK_DELETE) {
                $self->on_remove_object->() if $self->on_remove_object;
            } else {
                $event->Skip;
            }
        }
    });

    EVT_CHAR($self, sub {
        my ($s, $event) = @_;
        if ($event->HasModifiers) {
            $event->Skip;
        } else {
            my $key = $event->GetKeyCode;
            if ($key == ord('l')) {
                $self->on_rotate_object_left->() if $self->on_rotate_object_left;
            } elsif ($key == ord('r')) {
                $self->on_rotate_object_right->() if $self->on_rotate_object_right;
            } elsif ($key == ord('s')) {
                $self->on_scale_object_uniformly->() if $self->on_scale_object_uniformly;
            } elsif ($key == ord('+')) {
                $self->on_increase_objects->() if $self->on_increase_objects;
            } elsif ($key == ord('-')) {
                $self->on_decrease_objects->() if $self->on_decrease_objects;
            } else {
                $event->Skip;
            }
        }
    });
    
    return $self;
}

sub set_on_select_object {
    my ($self, $cb) = @_;
    $self->{on_select_object} = $cb;
}

sub set_on_double_click {
    my ($self, $cb) = @_;
    $self->on_double_click($cb);
}

sub set_on_right_click {
    my ($self, $cb) = @_;
    $self->on_right_click($cb);
}

sub set_on_rotate_object_left {
    my ($self, $cb) = @_;
    $self->on_rotate_object_left($cb);
}

sub set_on_rotate_object_right {
    my ($self, $cb) = @_;
    $self->on_rotate_object_right($cb);
}

sub set_on_scale_object_uniformly {
    my ($self, $cb) = @_;
    $self->on_scale_object_uniformly($cb);
}

sub set_on_increase_objects {
    my ($self, $cb) = @_;
    $self->on_increase_objects($cb);
}

sub set_on_decrease_objects {
    my ($self, $cb) = @_;
    $self->on_decrease_objects($cb);
}

sub set_on_remove_object {
    my ($self, $cb) = @_;
    $self->on_remove_object($cb);
}

sub set_on_instances_moved {
    my ($self, $cb) = @_;
    $self->{on_instances_moved} = $cb;
}

sub set_on_wipe_tower_moved {
    my ($self, $cb) = @_;
    $self->{on_wipe_tower_moved} = $cb;
}

sub set_on_model_update {
    my ($self, $cb) = @_;
    $self->on_model_update($cb);
}

sub reload_scene {
    my ($self, $force) = @_;

    $self->reset_objects;
    $self->update_bed_size;

    if (! $self->IsShown && ! $force) {
        $self->{reload_delayed} = 1;
        return;
    }

    $self->{reload_delayed} = 0;

    foreach my $obj_idx (0..$#{$self->{model}->objects}) {
        my @volume_idxs = $self->load_object($self->{model}, $self->{print}, $obj_idx);
        if ($self->{objects}[$obj_idx]->selected) {
            $self->select_volume($_) for @volume_idxs;
        }
    }
    if (defined $self->{config}->nozzle_diameter) {
        # Should the wipe tower be visualized?
        my $extruders_count = scalar @{ $self->{config}->nozzle_diameter };
        # Height of a print.
        my $height = $self->{model}->bounding_box->z_max;
        # Show at least a slab.
        $height = 10 if $height < 10;
        if ($extruders_count > 1 && $self->{config}->single_extruder_multi_material && $self->{config}->wipe_tower &&
            ! $self->{config}->complete_objects) {
            $self->volumes->load_wipe_tower_preview(1000, 
                $self->{config}->wipe_tower_x, $self->{config}->wipe_tower_y, 
                $self->{config}->wipe_tower_width, $self->{config}->wipe_tower_per_color_wipe * ($extruders_count - 1),
                $self->{model}->bounding_box->z_max, $self->UseVBOs);
        }
    }
}

sub update_bed_size {
    my ($self) = @_;
    $self->set_bed_shape($self->{config}->bed_shape);
}

# Called by the Platter wxNotebook when this page is activated.
sub OnActivate {
    my ($self) = @_;
    $self->reload_scene(1) if ($self->{reload_delayed});
}

1;
