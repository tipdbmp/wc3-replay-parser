package WC3ReplayParser;
use strict;
use warnings FATAL => 'all';
use v5.14;
use File::Slurp qw|slurp write_file|;
use Data::ParseBinary;
use Compress::Zlib;
use List::Util qw|min any none all|;
use List::MoreUtils qw|first_value first_index|;
use List::UtilsBy qw|sort_by|;
use File::Basename ();
use JSON::PP;
use vars qw|$game_patch_number $prev_location|;
use constant {
    BYTES_FOR_DECOMPRESSED_BLOCK             => 8192,
    STRING_ENCODED_ITEM_ID_MIN_DECIMAL_VALUE => 1093677104, # raw code 'A000'
    DUBLICATE_ITEM_ID_THRESHOLD              => 1000,       # milliseconds
};

# A block could mean 4 things:
#
# 1) a chunk of 8192 bytes (\x{00} padded to 8192 if necesery, only the last block (the first if there is only 1) is \x{00} padded),
#    after zlib decompression;
#    $header->{'number_of_compressed_data_blocks'} holds the number of those blocks.
#
# 2) inside of the above blocks there are replay data blocks
#    as described in w3g_format.txt 5.0 [ReplayData]
#
# 3) one of the "replay data blocks" is the TimeSlot block,
#    it contains command data, which is sort of like
#    a list of players of list of player actions (I think...)
#
# 4) the above player actions are also called "action_block"(s)


if (!caller) {
    # my $replay = parse('../replays/custom-ffa/orc-maphack.w3g');
    # my $replay = parse('../replays/hm.w3g');
    # my $replay = parse('../replays/drap.w3g');
    # my $replay = parse('../replays/1vs1/01.w3g'); # http://www.ffareplays.com/parse.php?file=Replay_2014_02_23_0415
    # my $replay = parse('../replays/ladder/1vs1-orc-vs-orc.w3g');
    # my $replay = parse('../replays/orc-start-5-peons-1-burrow.w3g');
    # my $replay = parse('../replays/hu-vs-orc.w3g'); # http://w3g.replays.net/doc/cn/2014-6-9/14023280572430069382.html
    # my $replay = parse('../replays/yroman.w3g');
    # my $replay = parse('../replays/visibility/hide_terrain.w3g');
    # my $replay = parse('../replays/visibility/map_explored.w3g');
    # my $replay = parse('../replays/visibility/always_visible.w3g');
    # my $replay = parse('../replays/visibility/default.w3g');
    # my $replay = parse('../replays/more_advanced_settings/random_hero.w3g');
    # my $replay = parse('../replays/1vs1/01.w3g');
    # my $replay = parse('../replays/1vs1/02.w3g');
    # my $replay = parse('../replays/1vs1/03.w3g');
    # my $replay = parse('../replays/ffa/01.w3g');
    # my $replay = parse('../replays/ffa/02.w3g');
    # my $replay = parse('../replays/ffa/03.w3g');
    # my $replay = parse('../replays/ffa/04-wtf-pitlord.w3g');
    # my $replay = parse('../replays/ffa/05.w3g');
    # my $replay = parse('../replays/ffa/06-crashing-w3g-julas.w3g');
    # my $replay = parse('../replays/ffa/07.w3g');
    # my $replay = parse('../replays/ffa/08.w3g');
    # my $replay = parse('../replays/ffa/09.w3g');
    # my $replay = parse('../replays/ffa/10.w3g');
    # my $replay = parse('../replays/tome-of-retraining/bl2we2a1.w3g');
    # my $replay = parse('../replays/tome-of-retraining/bl3a2.w3g');
    # my $replay = parse('../replays/tome-of-retraining/try-to-detect-tor.w3g');
    # my $replay = parse('../replays/tome-of-retraining/try-to-detect-tor2.w3g');
    # my $replay = parse('../replays/tome-of-retraining/enter-hero-skill-submenu.w3g');
    # my $replay = parse('../replays/tome-of-retraining/pick-up-tome-of-retraining.w3g');
    # my $replay = parse('../replays/tome-of-retraining/last-selected-unit-is-hero.w3g');
    # my $replay = parse('../replays/tome-of-retraining/live-game-1.w3g');
    # my $replay = parse('../replays/tome-of-retraining/wrong-ability-level.w3g');
    # my $replay = parse('../replays/units/2-footmen.w3g');
    # my $replay = parse('../replays/units/3-footmen-same-time.w3g');
    # my $replay = parse('../replays/units/4-footmen-same-time.w3g');
    # my $replay = parse('../replays/units/4-footmen-diff-times.w3g');
    # my $replay = parse('../replays/units/2-rax-2-farms-selected-2-foots-2-riflemen.w3g');
    # my $replay = parse('../replays/units/selection-2-rax-1-altar-1-armory.w3g');
    # my $replay = parse('../replays/units/subselection-2-rax-1-altar-1-armory.w3g');
    # my $replay = parse('../replays/units/shredder.w3g');
    # my $replay = parse('../replays/units/double-click-a-rax-4-rax.w3g');
    # my $replay = parse('../replays/units/ctrl-click-a-rax-4-rax.w3g');
    # my $replay = parse('../replays/units/building-1-rax.w3g');
    # my $replay = parse('../replays/units/1-rax-2-as.w3g');
    # my $replay = parse('../replays/units/1-rax-1-ars-1-workshop.w3g');
    # my $replay = parse('../replays/units/1-foot-1-sorc-1-mort.w3g');
    # my $replay = parse('../replays/units/2-foots-2-sorcs-2-morts.w3g');

    # my $replay = parse('C:/games/warcraft3/Warcraft III/Warcraft III/replay/LastReplay.w3g');


    # use Data::Dump; say Data::Dump::dump $replay;
    # # use DDP; say p $replay;
    # # my $json = JSON::PP->new->utf8->pretty->space_before(0)->indent_length(4)->encode($replay);
    # my $json = JSON::PP->new->pretty->space_before(0)->indent_length(4)->encode($replay);
    # write_file '../wc3-replay-visual/replay.json', $json;
    # # use Encode; use DDP; say encode 'UTF-8', p $replay;
}


sub parse { my ($filename_or_ref_bytes) = @_;
    my $replay_bytes = ref $filename_or_ref_bytes eq 'SCALAR' ? $$filename_or_ref_bytes
                     :                                          scalar slurp $filename_or_ref_bytes, binmode => ':bytes'
                     ;

    my $header = _header()->parse($replay_bytes);
    # say $header->{'number_of_compressed_data_blocks'};
    # use Encode; use DDP; say encode 'UTF-8', p $header;
    local $game_patch_number = $header->{'game_patch_number'};
    my $gmp_info = _game_map_players_info()->parse(_zlib_decompress($header->{'game_map_players_info'}{'compressed_data'}));

    my $all_replay_data = join '',
        $gmp_info->{'replay_data_bytes_from_gmp_block'},
        map { _zlib_decompress($_->{'compressed_data'}) } @{ $header->{'replay_data'} },
        ;

    # say length $all_replay_data;
    # Only the last block (the first if there is only 1) is \x{00}
    # padded up to BYTES_FOR_DECOMPRESSED_BLOCK number of bytes.
    # Removing the padding could save some function calls.
    $all_replay_data =~ s/\x{00}+$//g;
    # But make sure we don't corrupt the last data.
    $all_replay_data .= "\x{00}" x 4;
    # say length $all_replay_data;
    # exit 1;

    my $parsed_replay_data = _replay_data_loop()->parse($all_replay_data);
    $parsed_replay_data    = _filter_useless_blocks($parsed_replay_data);

    # _debug_action_blocks($parsed_replay_data); my ($players, $chat, $game_duration) = ({}, [], 0);
    my ($players, $chat, $game_duration) = _ginormous_fucking_loop($parsed_replay_data);
    # use DDP; say p $players;

    #  # PX3W => W3XP; 3RAW => WAR3
    $header->{'game_version_string'} = scalar reverse $header->{'game_version_string'};
    # use Encode; use DDP; say encode 'UTF-8', p $header;
    $gmp_info->{'map_settings'}      = _decode_map_settings($gmp_info->{'map_settings'});
    # delete $gmp_info->{'replay_data_bytes_from_gmp_block'};
    # use Encode; use DDP; say encode 'UTF-8', p $gmp_info;
    # exit 1;
    # use Encode; use Data::Dump; say encode 'UTF-8', Data::Dump::dump $gmp_info;

    _replay($header, $gmp_info, $players, $chat, $game_duration);
}

sub _header {
    state $header =
    Struct('header',
        Magic("Warcraft III recorded game\x1a\x00"),
        ULInt32('file_offset_of_first_compressed_data_block'),
        ULInt32('file_size'),
        Enum(ULInt32('game_version_flag'), ROC => 0, TFT => 1),
        ULInt32('overall_size_of_decompressed_data_excluding_replay_header'),
        ULInt32('number_of_compressed_data_blocks'),
        String('game_version_string', 4),
        ULInt32('game_patch_number'), # 1.xx
        ULInt16('game_build_number'),
        Enum(ULInt16('game_is_multiplayer'), 0 => 0x0000, 1 => 0x8000),
        ULInt32('replay_duration_in_ms'),
        ULInt32('CRC32_checksum_for_replay_header'),

        Struct('game_map_players_info',
            ULInt16('size_of_compressed_data_block'),
            ULInt16('size_of_decompressed_data_block'), # 8192 bytes
            ULInt32('unknown_probably_checksum'),
            Field('compressed_data', sub { $_->ctx->{'size_of_compressed_data_block'};}),
        ),

        # Array(2,
        # Array(sub { min 2, $_->ctx->{'number_of_compressed_data_blocks'} - 1 },
        Array(sub { $_->ctx->{'number_of_compressed_data_blocks'} - 1 },
            Struct('replay_data',
                ULInt16('size_of_compressed_data_block'),
                ULInt16('size_of_decompressed_data_block'),
                ULInt32('unknown_probably_checksum'),
                Field('compressed_data', sub { $_->ctx->{'size_of_compressed_data_block'} }),
            ),
        ),
    );
}

sub _game_map_players_info {
    state $game_map_players_info =
    Struct('game_info',
        Field('unknown', 4),
        # ULInt32('unknown', 4),
        Struct('game_creator',
            Byte('record_id'),
            _player_record(),
        ),
        CString('game_name'),
        Byte('null_byte'),
        CString('map_settings'),
        ULInt32('number_of_players'),
        Enum(Byte('game_type'),
            unknown_or_custom_game => 0x00,
            ladder_or_ffa          => 0x01,
            unknown_or_custom_game => 0x05,
            custom_game            => 0x09,
            single_player          => 0x1d,
            ladder_team_game       => 0x20,
        ),
        Enum(Byte('game_is_public'),
            1 => 0x00,
            0 => 0x08,
            2 => 0xC0,
        ),
        ULInt16('unknown'),
        ULInt32('unknown_maybe_language_id_or_checksum'),

        RepeatUntil(sub { $_->obj->{'record_id'} != 0x16 },
            Struct('players',
                Byte('record_id'),
                If(sub { $_->ctx->{'record_id'} == 0x16 },
                    Struct('player',
                        _player_record(),
                        ULInt32('unknown'),
                    ),
                ),
            ),
        ),

        Struct('GameStartRecord',
            # Byte('record_id'), <-- always 0x19 but we "consumed it" above before the If(... == 0x16)
            ULInt16('number_of_bytes_following'),
            Byte('number_of_slot_records_following'),
            Array(sub { $_->ctx->{'number_of_slot_records_following'} },
                _slot_record(),
            ),
            ULInt32('random_seed'),
            Enum(Byte('select_mode'),
                team_and_race_selectable     => 0x00,
                only_race_selectable         => 0x01, # fixed alliances in WorldEditor
                team_and_race_not_selectable => 0x03, # fixed player properties in WorldEditor
                only_team_selectable         => 0x04, # map advanced settings / random races enabled
                automated_match_making       => 0xcc,
            ),
            Byte('number_of_start_positions'),
        ),

        Field('replay_data_bytes_from_gmp_block', sub { BYTES_FOR_DECOMPRESSED_BLOCK() - $_->stream->{'location'} }),
    );
}

sub _player_record {
    state $player_record =
    Struct('PlayerRecord',
        Byte('id'),
        CString('name'),
        Enum(Byte('game_setting'), custom => 0x01, ladder => 0x08),
        IfThenElse('info', sub { $_->ctx->{'game_setting'} eq 'custom' },
            Byte('null_byte'),
            Struct('game_type_info_for_ladder_game',
                ULInt32('runtime_of_player_s_wc3_exe_in_milliseconds'),
                Enum(ULInt32('race'),
                    human    => 0x01,
                    orc      => 0x02,
                    nightelf => 0x04,
                    undead   => 0x08,
                    daemon   => 0x10,
                    random   => 0x20,
                    selectable_or_fixed => 0x40,
                ),
            ),
        ),
    ),
    ;
}

sub _slot_record {
    state $slot_record =
    Struct('SlotRecord',
        Byte('player_id'), # 0x00 for computers
        Byte('map_download_percent'),
        Enum(Byte('slot_status'),
            empty  => 0x00,
            closed => 0x01,
            used   => 0x02,
        ),
        Byte('is_ai'),
        Byte('team_number'),  # 0 .. 11; team 12 is for referees/observers
        Byte('color_number'), # 0 .. 11;
        Enum(Byte('race'),
            human    => 0x01, human    => 0x41,
            orc      => 0x02, orc      => 0x42,
            nightelf => 0x04, nightelf => 0x44,
            undead   => 0x08, undead   => 0x48,
            random   => 0x20, random   => 0x60,
            selectable_or_fixed => 0x40,
        ),
        If(sub { $game_patch_number >= 3 },
            Enum(Byte('ai_strength'),
                easy   => 0x00,
                normal => 0x01, # also for non-AI players
                insane => 0x02,
                wtf    => 0x64,
            ),
        ),
        If(sub { $game_patch_number >= 7 },
            Byte('handicap'), # in percent: 50, 60, 70, 80, 90 and 100
        ),
    ),
    ;
}

sub _decode_map_settings { my ($encoded_str) = @_;
    # Example decompression code (in 'C'):

    # char* EncodedString;
    # char* DecodedString;
    # char  mask;
    # int   pos=0;
    # int   dpos=0;

    # while (EncodedString[pos] != 0)
    # {
    #   if (pos%8 == 0) mask=EncodedString[pos];
    #   else
    #   {
    #     if ((mask & (0x1 << (pos%8))) == 0)
    #       DecodedString[dpos++] = EncodedString[pos] - 1;
    #     else
    #       DecodedString[dpos++] = EncodedString[pos];
    #   }
    #   pos++;
    # }

    my $decoded_str = '';
    my $mask;
    for my $pos (0 .. length($encoded_str) - 1) {
        if ($pos % 8 == 0) {
            $mask = ord substr $encoded_str, $pos, 1;
        } else {
            if ( ( $mask & ( 0x1 << ($pos % 8) ) ) == 0) {
                $decoded_str .= chr(ord(substr $encoded_str, $pos, 1) - 1);
            } else {
                $decoded_str .= substr $encoded_str, $pos, 1;
            }
        }
    }

    _map_settings()->parse($decoded_str);
}

sub _map_settings {
    state $map_settings =
    Struct('MapSettings',
        Enum(Byte('game_speed'),
            slow   => 0b00,
            normal => 0b01,
            fast   => 0b10,
            # unused => 0b11,
        ),
        ReversedBitStruct('advanced_settings',
            Enum(ReversedBitField('visibility', 4),
                unknown        => 0b0000, # ?!
                hide_terrain   => 0b0001,
                map_explored   => 0b0010,
                always_visible => 0b0100,
                default        => 0b1000,
            ),
            Enum(ReversedBitField('observer', 2),
                no_observers   => 0b00,
                unused         => 0b01,
                obs_on_defeat  => 0b10,
                full_observers => 0b11,
            ),
            Bit('teams_together'), # team members are placed at neighbored places
        ),
        Enum(BitField('lock_teams', 3), 0 => 0b000, 1 => 0b110),
        ReversedBitStruct('more_advanced_settings',
            Bit('full_shared_unit_control'),
            Bit('random_hero'),
            Bit('random_races'),
            Bit('unknown1'),
            Bit('unknown2'),
            Bit('unknown3'),
            Bit('observer_referees'),
        ),
        Byte('null_byte1'),
        Byte('unknown1'),
        Byte('null_byte2'),
        Byte('unknown2'),
        Byte('null_byte3'),
        ULInt32('checksum'),
        CString('map_name'),
        CString('game_creator_name'),
        CString('always_empty_string'),
    ),
    ;
}

sub _replay_data_loop {
    state $replay_data_loop =
    RepeatUntil(sub { $_->stream->{'location'} == $_->stream->{'length'} },
        _replay_data(),
    ),
    ;
}

sub _replay_data {
    state $replay_data =
    Struct('replay_data',
        Byte('block_id'),
        Switch('block', sub { $_->ctx->{'block_id'} }, {
        # Switch('block', sub { say $_->stream->{'location'}; $_->ctx->{'block_id'} }, {
            0x17 => _block_leave_game(),
            0x1A => _block_0x1A(),
            0x1B => _block_0x1B(),
            0x1C => _block_0x1C(),
            0x1E => _block_time_slot(),
            0x1F => _block_time_slot(),
            0x20 => _block_0x20(), # for patch > 1.02 means chat message
            0x22 => _block_0x22(),
            0x23 => _block_0x23(),
            0x2F => _block_forced_game_end_countdown(),
        },
            # default => If(sub { say $_->ctx->{'block_id'}; 0 }, Byte('foo')),
            default => If(sub { 0 }, Byte('foo')),
        ),
    ),
    ;
}

sub _block_leave_game {
    state $b =
    Struct('block_leave_game',
        Enum(ULInt32('reason'),
            connection_closed_by_remote_game  => 0x01,
            connection_closed_by_local_game   => 0x0C,
            # unknown_and_rare_almost_like_0x01 => 0x0E,
            divine_intervention               => 0x0E,
        ),
        Byte('player_id'),
        ULInt32('result'),
        ULInt32('unknown'),
    ),
    ;
}

sub _block_0x1A { state $b = ULInt32('unknown'); }
sub _block_0x1B { state $b = ULInt32('unknown'); }
sub _block_0x1C { state $b = ULInt32('unknown'); }

sub _block_time_slot {
    state $b =
    Struct('block_time_slot',
        ULInt16('number_of_bytes_following'),
        ULInt16('time_increment'),
        If(sub { $_->ctx->{'number_of_bytes_following'} > 2 },
            Field('command_data', sub {
                # min +($_->ctx->{'number_of_bytes_following'} - 2), ($_->stream->{'length'} - $_->stream->{'location'});
                $_->ctx->{'number_of_bytes_following'} - 2;
            }),
        ),
    ),
    ;
}

sub _block_0x20 {
    IfThenElse('block_0x20', sub { $game_patch_number > 2 },
        _block_player_chat_message(),
        _block_0x22(),
    ),
}

sub _block_player_chat_message {
    state $b =
    Struct('block_player_chat_message',
        Byte('player_id'),
        ULInt16('number_of_bytes_following'),
        Enum(Byte('type'), delayed => 0x10, normal => 0x20),
        If(sub { $_->ctx->{'type'} eq 'normal' },
            Enum(ULInt32('recipient'),
                all_players  => 0x00,
                allies       => 0x01,
                observers    => 0x02, # or referees
                player_1     => 0x03 + 0,
                player_2     => 0x03 + 1,
                player_3     => 0x03 + 2,
                player_4     => 0x03 + 3,
                player_5     => 0x03 + 4,
                player_6     => 0x03 + 5,
                player_7     => 0x03 + 6,
                player_8     => 0x03 + 7,
                player_9     => 0x03 + 8,
                player_10    => 0x03 + 9,
                player_11    => 0x03 + 10,
                player_12    => 0x03 + 11,
                player_13    => 0x03 + 12,
                player_14    => 0x03 + 13,
                player_15    => 0x03 + 14,
                player_16    => 0x03 + 15,
            ),
        ),
        CString('message'),
    ),
    ;
}

sub _block_0x22 {
    state $b =
    Struct('block_0x22_checksum_or_random_number_seed_for_next_frame',
        Byte('number_of_bytes_following'), # always 4 so far
        ULInt32('unknown_very_random'),
    ),
    ;
}

sub _block_0x23 {
    state $b =
    Struct('block_0x23',
        ULInt32('unknown1'),
        Byte('unknown2'),
        ULInt32('unknown3'),
        Byte('unknown4'),
    ),
    ;
}

sub _block_forced_game_end_countdown {
    state $b =
    Struct('block_forced_game_end_countdown',
        Enum(ULInt32('type'),
            countdown_is_running => 0x00,
            countdown_is_over    => 0x01,
        ),
        ULInt32('countdown_time_in_seconds'),
    ),
    ;
}

sub _block_name_to_id { my ($block_name) = @_;
    state $map = {
        leave_game => 0x17,
        ($game_patch_number > 2 ? (time_slot => 0x1F) : (time_slot => 0x1E) ),
        player_chat_message => 0x20,
    };
    $map->{$block_name};
}

sub _filter_useless_blocks { my ($blocks) = @_;
    state $block_leave_game_id          = _block_name_to_id('leave_game');
    state $block_time_slot_id           = _block_name_to_id('time_slot');
    state $block_player_chat_message_id = _block_name_to_id('player_chat_message');

    [
        # grep {
        #     $_->{'block_id'} != $block_time_slot_id ? 1 : defined $_->{'block'}{'command_data'}
        # }

        grep {
            my $b = $_;
            any { $b->{'block_id'} == $_ } $block_leave_game_id, $block_time_slot_id, $block_player_chat_message_id,
        } @$blocks
    ];
}


sub _command_data_player {
    state $command_data_player =
    Struct('command_data_player',
        # Byte('player_id'),
        # ULInt16('action_block_length'),
        # _action_block(),

        # RepeatUntil(sub {
        #     $_->stream->{'location'} >= $_->stream->{'length'}
        # },
        #     _action_block(),
        # ),

        # Array(5,
        RepeatUntil(sub {
        #     # say 'location: ', $_->stream->{'location'}, '; length: ', $_->stream->{'length'};
        #     # use DDP; say p $_->obj;
        #     # exit 1;
        #     say 'player_id: ', $_->obj->{'player_id'};
            $_->stream->{'location'} == $_->stream->{'length'}
        #     # exit 1;
        #     # $_->obj->{'player_id'} != 0;
        },
            Struct('command_data_player',
                Byte('player_id'),
                ULInt16('action_block_length'),
                Field('player_actions', sub { $_->ctx->{'action_block_length'} }),

                # _action_block(),
                # RepeatUntil(sub {
                #     # use DDP; say p $_;
                #     # use DDP; say p $_->obj;
                #     # exit 1;
                #     local $prev_location = $_->stream->{'location'};
                #     say 'action_block_length: ', $_->{'ctx'}[1]{'action_block_length'},
                #         '; location: ', $_->stream->{'location'},
                #         '; prev_location: ',  $prev_location,
                #         '; length:   ', $_->stream->{'length'},
                #         ;
                #     # $_->stream->{'location'} == $_->{'ctx'}[1]{'action_block_length'};
                # },
                #     _action_block(),
                # )
            ),
        ),
    ),
    ;
}

sub _command_data_player_actions {
    state $command_data_player_actions =
    Struct('command_data_player_actions',
        RepeatUntil(sub { $_->stream->{'location'} == $_->stream->{'length'} },
            _action_block(),
        ),
    ),
    ;
}

sub _action_block {
    state $action_block =
    Struct('action_block',
        Byte('action_id'),

        Switch('action', sub {
            # say 'action_id: ', $_->ctx->{'action_id'};
            # use DDP; say p $_;
            # exit 1;
            # say '!', $_->{'ctx'}[1]{'action_block_length'}, '!';
            $_->ctx->{'action_id'}
        }, {
            # 0x00 => Byte('null_byte'),
            0x01 => _action_pause_game(),
            0x02 => _action_resume_game(),
            0x03 => _action_single_player_set_game_speed(),
            0x04 => _action_single_player_increase_game_speed(),
            0x05 => _action_single_player_decrease_game_speed(),
            0x06 => _action_save_game(),
            0x07 => _action_save_game_finished(),

            0x10 => _action_unit_ability_no_target(),
            0x11 => _action_unit_ability_target_loc(),
            0x12 => _action_unit_ability_target_widget_or_loc(),
            0x13 => _action_unit_give_item_or_drop_on_ground(),
            0x14 => _action_unit_ability_double_targets_and_locs(), # e.g: townhall right click on a tree

            0x16 => _action_change_selection(),
            0x17 => _action_assign_group_hotkey(),
            0x18 => _action_select_group_hotkey(),
            0x19 => _action_select_subgroup(),
            0x1A => _action_0x1A(),
            0x1B => _action_0x1B(),
            0x1C => _action_0x1C(),
            0x1D => _action_0x1D(),
            0x1E => _action_remove_unit_from_building_queue(),  #_action_0x1E(),
            # 0x1F => If(sub { 0 }, Byte('no_additional_data'),),

            0x21 => _action_unknown_2(),
            0x20 => _action_single_player_cheat_fast_cooldown(),
            0x22 => _action_single_player_cheat_instant_defeat(),
            0x23 => _action_single_player_cheat_fast_construction(),
            0x24 => _action_single_player_cheat_fast_decay(),
            0x25 => _action_single_player_cheat_no_food_limit(),
            0x26 => _action_single_player_cheat_god_mode(),
            0x27 => _action_single_player_cheat_keyser_soze(),
            0x28 => _action_single_player_cheat_lumber(),
            0x29 => _action_single_player_cheat_there_is_no_spoon(),
            0x2A => _action_single_player_cheat_no_defeat(),
            0x2B => _action_single_player_cheat_itvexesme(),
            0x2C => _action_single_player_cheat_who_is_john_galt(),
            0x2D => _action_single_player_cheat_greed_is_good(),
            0x2E => _action_single_player_cheat_set_time_of_day(),
            0x2F => _action_single_player_cheat_i_see_dead_people(),
            0x30 => _action_single_player_cheat_disable_tech_tree_requirements(),
            0x31 => _action_single_player_cheat_research_upgrades(),
            0x32 => _action_single_player_cheat_all_your_base_are_belong_to_us(),

            0x50 => _action_change_ally_options(),
            0x51 => _action_transfer_resources(),

            0x60 => _action_map_trigger_chat_command(),
            0x61 => _action_esc_pressed(),
            0x62 => _action_scenario_trigger(),

            0x65 => _action_enter_choose_hero_skill_submenu(),
            0x66 => _action_0x66(),
            0x67 => _action_0x67(),
            0x68 => _action_0x68(),
            0x69 => _action_0x69(),
            0x6A => _action_continue_game_block_a(), # _action_0x6A(),

            0x75 => _action_unknown_3(),
        },
            # default => Byte('foo')
            default => If(sub { 0 }, Byte('no_additional_data'),),
        ),
    ),
    ;
}

sub _action_pause_game {
    state $action_pause_game =
    Struct('action_pause_game',
        If(sub { 0 }, Byte('no_additional_data'),),
    ),
    ;
}

sub _action_resume_game {
    state $action_resume_game =
    Struct('action_resume_game',
        If(sub { 0 }, Byte('no_additional_data'),),
        # Byte('no_additional_data'),
    ),
    ;
}

sub _action_single_player_set_game_speed {
    state $action_sinle_player_set_game_speed =
    Struct('action_sinle_player_set_game_speed',
        Enum(Byte('game_speed'), slow => 0x00, normal => 0x01, fast => 0x02),
    ),
    ;
}

sub _action_single_player_increase_game_speed {
    state $action_single_player_increase_game_speed =
    Struct('action_single_player_increase_game_speed',
        If(sub { 0 }, Byte('no_additional_data'),),
    ),
    ;
}

sub _action_single_player_decrease_game_speed {
    state $action_single_player_decrease_game_speed =
    Struct('action_single_player_decrease_game_speed',
        If(sub { 0 }, Byte('no_additional_data'),),
    ),
    ;
}

sub _action_save_game {
    state $action_save_game =
    Struct('action_save_game',
        CString('savegame_name'),
    ),
    ;
}

sub _action_save_game_finished {
    state $action_save_game_finished =
    Struct('action_save_game_finished',
        ULInt32('unknown'), # seems to always be 0x00000001
    ),
    ;
}

sub _action_unit {
    state $action_unit =
    Struct('action_unit',
        IfThenElse('ability_flags', sub { $game_patch_number < 13 },
            Byte('ability_flags'),
            ULInt16('ability_flags'),
        ),
        ULInt32('item_id'),
        If(sub { $game_patch_number >= 7 },
            Struct('unknown',
                ULInt32('unknown_a'),
                ULInt32('unknown_b'),
            ),
        ),
    ),
    ;
}

sub _action_unit_ability_no_target {
    state $action_unit_ability =
    Struct('action_unit_ability_no_target',
        _action_unit(),
    ),
    ;
}

sub _action_unit_loc {
    state $action_unit_loc =
    Struct('action_unit_loc',
        ULInt32('loc_x'),
        ULInt32('loc_y'),
    ),
    ;
}

sub _action_unit_ability_target_loc {
    state $action_unit_ability_target_loc =
    Struct('action_unit_ability_target_loc',
        _action_unit(),
        _action_unit_loc(),
    ),
    ;
}

sub _action_unit_loc_target {
    state $action_unit_loc_target =
    Struct('action_unit_loc_target',
        _action_unit(),
        _action_unit_loc(),
        ULInt32('unit_id'),
        ULInt32('target_widget_id'),
    ),
    ;
}

sub _action_unit_ability_target_widget_or_loc {
    state $action_unit_ability_target_widget_or_loc =
    Struct('action_unit_ability_target_widget_or_loc',
        _action_unit_loc_target(),
    ),
    ;
}

sub _action_unit_give_item_or_drop_on_ground {
    state $action_unit_give_item_or_drop_on_ground =
    Struct('action_unit_give_item_or_drop_on_ground',
        _action_unit_loc_target(),
        # item_1_id = item_2_id = 0xFFFFFFFF for droping the item on the ground
        ULInt32('item_1_id'),
        ULInt32('item_2_id'),
    ),
    ;
}

sub _action_unit_ability_double_targets_and_locs {
    state $action_unit_ability_double_targets_and_locs =
    Struct('action_unit_ability_double_targets_and_locs',
        IfThenElse('ability_flags', sub { $game_patch_number < 13 },
            Byte('ability_flags'),
            ULInt16('ability_flags'),
        ),
        ULInt32('item_id_a'),
        If(sub { $game_patch_number >= 7 },
            Struct('unknown',
                ULInt32('unknown_a'),
                ULInt32('unknown_b'),
            ),
        ),
        ULInt32('target_loc_x_a'),
        ULInt32('target_loc_y_a'),
        ULInt32('item_id_a'),
        Field('unknown', 9),
        ULInt32('target_loc_x_b'),
        ULInt32('target_loc_y_b'),
    ),
    ;
}

sub _action_change_selection {
    state $action_change_selection =
    Struct('action_change_selection',
        Enum(Byte('selection_mode'), add_to_selection => 0x01, remove_from_selection => 0x02),
        ULInt16('number_of_units'), # including buildings
        Array(sub {
            $_->ctx->{'number_of_units'};
        },
            Struct('object_id',
                ULInt32('object_id1'),
                ULInt32('object_id2'),
            ),
        ),
    ),
    ;
}

sub _action_assign_group_hotkey {
    state $action_assign_group_hotkey =
    Struct('action_assign_group_hotkey',
        Byte('group_number'), # key 1 is group 0, key 2 is group 1, ..., key 0 is group 9
        ULInt16('number_of_units_in_group'),
        Array(sub {
            $_->ctx->{'number_of_units_in_group'};
        },
            Struct('group',
                ULInt32('object_id1'),
                ULInt32('object_id2'),
            ),
        ),
    ),
    ;
}

sub _action_select_group_hotkey {
    state $action_select_group_hotkey =
    Struct('action_select_group_hotkey',
        Byte('group_number'),
        Byte('unknown'), # always 0x03
    ),
    ;
}

sub _action_select_subgroup {
    state $action_select_subgroup =
    Struct('action_select_subgroup',
        IfThenElse('action_select_subgroup', sub { $game_patch_number >= 14 },
            Struct('action_select_subgroup',
                ULInt32('item_id'),
                ULInt32('object_id1'),
                ULInt32('object_id2'),
            ),
            Struct('action_select_subgroup',
                Byte('subgroup_number'),
            ),
        ),
    ),
    ;
}

sub _action_unknown_1 {
    state $action_unknown_1 =
    Struct('action_unknown_1',
        Byte('unknown'),
        ULInt32('unknown_1'),
        ULInt32('unknown_2'),
    ),
    ;
}

sub _action_select_ground_item {
    state $action_select_ground_item =
    Struct('action_select_ground_item',
        Byte('unknown'),
        ULInt32('object_id1'),
        ULInt32('object_id2'),
    ),
    ;
}

sub _action_cancel_hero_revival {
    state $action_cancel_hero_revival =
    Struct('action_cancel_hero_revival',
        ULInt32('unit_id_1'),
        ULInt32('unit_id_2'),
    ),
    ;
}

sub _action_remove_unit_from_building_queue {
    state $action_remove_unit_from_building_queue =
    Struct('action_remove_unit_from_building_queue',
        Byte('slot_number'),
        ULInt32('unit_id'),
    ),
    ;
}

sub _action_unknown_2 {
    state $action_unkown_2 =
    Struct('action_unknown_2',
        ULInt32('unknown_a'),
        ULInt32('unknown_b'),
    ),
    ;
}

sub _action_single_player_cheat_fast_cooldown {
    state $s = Struct('action_single_player_cheat_fast_cooldown', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_instant_defeat {
    state $s = Struct('action_single_player_cheat_instant_defeat', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_fast_construction {
    state $s = Struct('action_single_player_cheat_fast_construction', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_fast_decay {
    state $s = Struct('action_single_player_cheat_fast_decay', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_no_food_limit {
    state $s = Struct('action_single_player_cheat_no_food_limit', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_god_mode {
    state $s = Struct('action_single_player_cheat_god_mode', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_keyser_soze { # gives gold
    state $s = Struct('action_single_player_cheat_keyser_soze',
        Byte('unknown'),
        SLInt32('amount'),
    ),
}
sub _action_single_player_cheat_lumber {
    state $s = Struct('action_single_player_cheat_lumber',
        Byte('unknown'),
        SLInt32('amount'),
    ),
}
sub _action_single_player_cheat_there_is_no_spoon { # unlimited mana
    state $s = Struct('action_single_player_cheat_there_is_no_spoon', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_no_defeat { # unlimited mana
    state $s = Struct('action_single_player_cheat_no_defeat', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_itvexesme { # disable victory conditions
    state $s = Struct('action_single_player_cheat_itvexesme', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_who_is_john_galt { # enable research
    state $s = Struct('action_single_player_cheat_who_is_john_galt', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_greed_is_good { # gold and lumber
    state $s = Struct('action_single_player_cheat_greed_is_good',
        Byte('unknown'),
        SLInt32('amount'),
    ),
}
sub _action_single_player_cheat_set_time_of_day {
    state $s = Struct('action_single_player_cheat_set_time_of_day',
        LFloat32('time'),
    ),
}
sub _action_single_player_cheat_i_see_dead_people {
    state $s = Struct('action_single_player_cheat_i_see_dead_people', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_disable_tech_tree_requirements {
    state $s = Struct('action_single_player_cheat_disable_tech_tree_requirements', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_research_upgrades {
    state $s = Struct('action_single_player_cheat_research_upgrades', If(sub { 0 }, Byte('no_additional_data'))),
}
sub _action_single_player_cheat_all_your_base_are_belong_to_us { # instant victory
    state $s = Struct('action_single_player_cheat_all_your_base_are_belong_to_us', If(sub { 0 }, Byte('no_additional_data'))),
}


sub _action_change_ally_options {
    state $action_change_ally_options =
    Struct('action_change_ally_options',
        Byte('player_slot_number'), # including AI players
        ReversedBitStruct('ally_options',
            Enum(ReversedBitField('allied_with_player', 5), # 0 .. 4
                0x1F => 1,
                0x00 => 0,
                _default_ => 1,
            ),
            Bit('sharing_vision_with_player'),              # 5
            Bit('sharing_unit_control_with_player'),        # 6
            IfThenElse('allied_victory', sub { $game_patch_number >= 7 },
                Struct('allied_victory',
                    ReversedBitField('foo', 3),             # 7, 8, 9
                    Bit('allied_victory'),                  # 10
                    ReversedBitField('bar', 21)             # 11 .. 31
                ),
                Struct('allied_victory',
                    ReversedBitField('foo', 2),             # 7, 8
                    Bit('allied_victory'),                  # 9
                    ReversedBitField('bar', 22)             # 10 .. 31
                ),
            ),
        ),
    ),
    ;
}

sub _action_transfer_resources {
    state $action_transfer_resources =
    Struct('action_transfer_resources',
        Byte('player_slot_number'),
        ULInt32('gold_amount'),
        ULInt32('lumber_amount'),
    ),
    ;
}

sub _action_map_trigger_chat_command {
    state $action_map_trigger_chat_command =
    Struct('action_map_trigger_chat_command',
        ULInt32('unknown_a'),
        ULInt32('unknown_b'),
        CString('chat_command_or_trigger_name'),
    ),
    ;
}

sub _action_esc_pressed {
    state $action_esc_pressed =
    Struct('action_esc_pressed',
        If(sub { 0 }, Byte('no_additional_data'),),
    ),
    ;
}

sub _action_scenario_trigger {
    state $action_scenario_trigger =
    Struct('action_scenario_trigger',
        ULInt32('unknown_a'),
        ULInt32('unknown_b'),
        If(sub { $game_patch_number >= 7 },
            ULInt32('unknown_counter'),
        ),
    ),
    ;
}

sub _action_enter_choose_hero_skill_submenu {
    state $action_enter_choose_hero_skill_submenu =
    Struct('action_enter_choose_hero_skill_submenu',
        If(sub { 0 }, Byte('no_additional_data')),
    ),
    ;
}

sub _action_enter_choose_building_submenu {
    state $action_enter_choose_building_submenu =
    Struct('action_enter_choose_building_submenu',
        If(sub { 0 }, Byte('no_additional_data')),
    ),
    ;
}

sub _action_minimap_signal {
    state $action_minimap_signal =
    Struct('action_minimap_signal',
        ULInt32('loc_x'),
        ULInt32('loc_y'),
        ULInt32('unknown'),
    ),
    ;
}

sub _action_continue_game_block_b {
    state $action_continue_game_block_b =
    Struct('action_continue_game_block_b',
        ULInt32('unknown_c'),
        ULInt32('unknown_d'),
        ULInt32('unknown_a'),
        ULInt32('unknown_b'),
    ),
    ;
}

sub _action_continue_game_block_a {
    state $action_continue_game_block_a =
    Struct('action_continue_game_block_a',
        ULInt32('unknown_a'),
        ULInt32('unknown_b'),
        ULInt32('unknown_c'),
        ULInt32('unknown_d'),
    ),
    ;
}

sub _action_unknown_3 {
    state $action_unknown_3 =
    Struct('action_unknown_3',
        Byte('unknown'),
    ),
    ;
}

sub _action_0x1A {
    IfThenElse('action_0x1A', sub { $game_patch_number > 14 },
        # in 1.15+ it's empty
        If(sub { 0 }, Byte('no_additional_data'),),

        _action_unknown_1(),
    ),
    ;
}

sub _action_0x1B {
    IfThenElse('action_0x1B', sub { $game_patch_number > 14 },
        _action_unknown_1(),
        _action_select_ground_item(),
    ),
    ;
}

sub _action_0x1C {
    IfThenElse('action_0x1C', sub { $game_patch_number > 14 },
        _action_select_ground_item(),
        _action_cancel_hero_revival(),
    ),
    ;
}

sub _action_0x1D {
    IfThenElse('action_0x1D', sub { $game_patch_number > 14 },
        _action_cancel_hero_revival(),
        _action_remove_unit_from_building_queue(),
    ),
    ;
}

sub _action_0x1E {
    # IfThenElse('action_0x1E', sub { $game_patch_number > 14 },
        _action_remove_unit_from_building_queue(),
    # ),
    ;
}

sub _action_0x66 {
    IfThenElse('action_0x66', sub { $game_patch_number > 6 },
        _action_enter_choose_hero_skill_submenu(),
        _action_enter_choose_building_submenu(),
    ),
    ;
}

sub _action_0x67 {
    IfThenElse('action_0x67', sub { $game_patch_number > 6 },
        _action_enter_choose_building_submenu(),
        _action_minimap_signal(),
    ),
    ;
}

sub _action_0x68 {
    IfThenElse('action_0x68', sub { $game_patch_number > 6 },
        _action_minimap_signal(),
        _action_continue_game_block_b(),
    ),
    ;
}

sub _action_0x69 {
    IfThenElse('action_0x69', sub { $game_patch_number > 6 },
        _action_continue_game_block_b(),
        _action_continue_game_block_a(),
    ),
    ;
}

sub _action_0x6A {
    # IfThenElse('action_0x6A', sub { $game_patch_number > 6 },
        _action_continue_game_block_a(),
        # _action_continue_game_block_a(),
    # ),
    ;
}

sub _actions {
    state $actions = {
        0x01 => 'pause_game',
        0x02 => 'resume_game',
        0x03 => 'sinle_player_set_game_speed',
        0x04 => 'single_player_increase_game_speed',
        0x05 => 'single_player_decrease_game_speed',
        0x06 => 'save_game',
        0x07 => 'save_game_finished',

        0x10 => 'unit_ability_no_target',
        0x11 => 'unit_ability_target_loc',
        0x12 => 'unit_ability_target_widget_or_loc',
        0x13 => 'unit_give_item_or_drop_on_ground',
        0x14 => 'unit_ability_double_targets_and_locs',

        0x16 => 'change_selection',
        0x17 => 'assign_group_hotkey',
        0x18 => 'select_group_hotkey',
        0x19 => 'select_subgroup',
        ($game_patch_number > 14 ? (0x1A => 'pre_subselection') : (0x1A => 'unknown_1')),
        ($game_patch_number > 14 ? (0x1B => 'unknown_1') : (0x1B => 'select_ground_item')),
        ($game_patch_number > 14 ? (0x1C => 'select_ground_item') : (0x1C => 'cancel_hero_revival')),
        ($game_patch_number > 14 ? (0x1D => 'cancel_hero_revival') : (0x1D => 'remove_unit_from_building_queue')),
        0x1E => 'remove_unit_from_building_queue',

        0x21 => 'unkown_2',
        0x20 => 'single_player_cheat_fast_cooldown',
        0x22 => 'single_player_cheat_instant_defeat',
        0x23 => 'single_player_cheat_fast_construction',
        0x24 => 'single_player_cheat_fast_decay',
        0x25 => 'single_player_cheat_no_food_limit',
        0x26 => 'single_player_cheat_god_mode',
        0x27 => 'single_player_cheat_keyser_soze',
        0x28 => 'single_player_cheat_lumber',
        0x29 => 'single_player_cheat_there_is_no_spoon',
        0x2A => 'single_player_cheat_no_defeat',
        0x2B => 'single_player_cheat_itvexesme',
        0x2C => 'single_player_cheat_who_is_john_galt',
        0x2D => 'single_player_cheat_greed_is_good',
        0x2E => 'single_player_cheat_set_time_of_day',
        0x2F => 'single_player_cheat_i_see_dead_people',
        0x30 => 'single_player_cheat_disable_tech_tree_requirements',
        0x31 => 'single_player_cheat_research_upgrades',
        0x32 => 'single_player_cheat_all_your_base_are_belong_to_us',

        0x50 => 'change_ally_options',
        0x51 => 'transfer_resources',

        0x60 => 'map_trigger_chat_command',
        0x61 => 'esc_pressed',
        0x62 => 'scenario_trigger',

        0x65 => 'enter_choose_hero_skill_submenu',
        ($game_patch_number > 6 ? (0x66 => 'enter_choose_hero_skill_submenu') : (0x66 => 'enter_choose_building_submenu')),
        ($game_patch_number > 6 ? (0x67 => 'enter_choose_building_submenu') : (0x67 => 'minimap_signal')),
        ($game_patch_number > 6 ? (0x68 => 'minimap_signal') : (0x68 => 'continue_game_block_b')),
        ($game_patch_number > 6 ? (0x69 => 'continue_game_block_b') : (0x69 => 'continue_game_block_a')),
        0x6A => 'continue_game_block_a',

        0x75 => 'unknown_3',
    };
}

sub _action_id_to_name { my ($aid) = @_;
    my $actions = _actions();

    my $v = $actions->{$aid};
    if (!defined $v) {
        say "nothing for '$aid'";
    }
    $actions->{$aid};
}

sub _action_name_to_id { my ($action_name) = @_;
    state $action_id_for_name;
    if (!$action_id_for_name) {
        $action_id_for_name = {};
        my $action_name_for_id = _actions();
        my @names = values %$action_name_for_id;
        my @ids = keys %$action_name_for_id;
        @{$action_id_for_name}{@names} = @ids;
    }
    $action_id_for_name->{$action_name};
}


sub _ginormous_fucking_loop { my ($parsed_replay_data) = @_;
    my $block_time_slot_id           = _block_name_to_id('time_slot');
    my $block_player_chat_message_id = _block_name_to_id('player_chat_message');
    my $block_leave_game_id          = _block_name_to_id('leave_game');

    my $action_unit_ability_no_target_id               = _action_name_to_id('unit_ability_no_target');
    my $action_unit_ability_target_loc_id              = _action_name_to_id('unit_ability_target_loc');
    my $action_unit_ability_target_widget_or_loc_id    = _action_name_to_id('unit_ability_target_widget_or_loc');
    # my $action_unit_give_item_or_drop_on_ground        = _action_name_to_id('unit_give_item_or_drop_on_ground');
    my $action_unit_ability_double_targets_and_locs_id = _action_name_to_id('unit_ability_double_targets_and_locs');
    # my $action_esc_pressed_id                          = _action_name_to_id('esc_pressed');
    my $action_change_selection_id                     = _action_name_to_id('change_selection');
    my $action_assign_group_hotkey_id                  = _action_name_to_id('assign_group_hotkey');
    my $action_select_group_hotkey_id                  = _action_name_to_id('select_group_hotkey');
    my $action_select_subgroup_id                      = _action_name_to_id('select_subgroup');
    my $action_pre_subselection_id                     = _action_name_to_id('pre_subselection');
    my $action_remove_unit_from_building_queue_id      = _action_name_to_id('remove_unit_from_building_queue');

    # APM = Actions-Per-Minute
    my $is_action_id_included_in_APM_calculation = {
        $action_unit_ability_no_target_id                          => 1,
        $action_unit_ability_target_loc_id                         => 1,
        $action_unit_ability_target_widget_or_loc_id               => 1,
        _action_name_to_id('unit_give_item_or_drop_on_ground')     => 1,
        _action_name_to_id('unit_ability_double_targets_and_locs') => 1,
        $action_change_selection_id                                => 1, # [APM]?
        $action_assign_group_hotkey_id                             => 1,
        $action_select_group_hotkey_id                             => 1,
        $action_select_subgroup_id                                 => 1, # [APM]?
        _action_name_to_id('select_ground_item')                   => 1,
        _action_name_to_id('cancel_hero_revival')                  => 1,
        $action_remove_unit_from_building_queue_id                 => 1,
        _action_name_to_id('esc_pressed')                          => 1,
        _action_name_to_id('enter_choose_hero_skill_submenu')      => 1,
        _action_name_to_id('enter_choose_building_submenu')        => 1,
    };

    my $players = {};
    my $time = 0;
    my $chat = [];
    my @leave_game_blocks;

    BLOCK:
    for my $block (@$parsed_replay_data) {
        if ($block_time_slot_id == $block->{'block_id'}) {
            $time += $block->{'block'}{'time_increment'};
            # say "\$time: $time";
            next BLOCK if !defined $block->{'block'}{'command_data'};

            my $parsed_command_data = _command_data_player()->parse($block->{'block'}{'command_data'});
            for my $command_data_player (@{ $parsed_command_data->{'command_data_player'} }) {
                my $player_id = $command_data_player->{'player_id'};

                my $parsed_player_actions = _command_data_player_actions()->parse($command_data_player->{'player_actions'});
                my $cp;
                my $action_id;
                PLAYER_ACTION:
                for my $action_block (@{ $parsed_player_actions->{'action_block'} }) {
                    $action_id = $action_block->{'action_id'};

                    if (!exists $players->{$player_id}) {
                        # if ($player_id == 5) {
                            # use Encode; use DDP; say encode 'UTF-8', p $action_block; exit 1;
                        # }
                        $players->{$player_id} = {
                            last => { time => 0, item_id => '', },
                            # build_order => [],
                            build_order => {},
                        };
                    }
                    # this action block is about the current player
                    $cp = $players->{$player_id};

                    # counting the actions for the APM calculation
                    if ($is_action_id_included_in_APM_calculation->{$action_id}) {
                        if ($action_select_subgroup_id == $action_id && $game_patch_number < 14) {
                            my $subgroup_number = $action_block->{'action'}{'action_select_sub'}{'subgroup_number'};
                            $cp->{'actions_count'}++ if $subgroup_number != 0x00 && $subgroup_number != 0xFF;
                        } elsif ($action_change_selection_id == $action_id) {
                            my $selection_mode = $action_block->{'action'}{'selection_mode'};

                            if ($selection_mode eq 'remove_from_selection') {
                                $cp->{'actions_count'}++;
                                $cp->{'last'}{'action_was_remove_from_selection'} = 1;
                            } else {
                                $cp->{'actions_count'}++ if !$cp->{'last'}{'action_was_remove_from_selection'};
                                $cp->{'last'}{'action_was_remove_from_selection'} = 0;
                            }
                        } else {
                            $cp->{'actions_count'}++;
                        }
                    } else {
                        $cp->{'last'}{'action_was_remove_from_selection'} = 0;
                    }

                    if (any { $action_id == $_ }
                        $action_unit_ability_no_target_id,
                        $action_unit_ability_target_loc_id) {

                        my $decimal_item_id = $action_block->{'action'}{'action_unit'}{'item_id'};
                        my $item_id = '';

                        if ($decimal_item_id >= STRING_ENCODED_ITEM_ID_MIN_DECIMAL_VALUE) {
                            $item_id = _decimal_to_string_encoded_item_id($decimal_item_id);

                            # if ($item_id eq 'Hmkg') {
                            #     say "\$time: $time";
                            #     say $time - $cp->{'last'}{'time'};
                            # }

                            next PLAYER_ACTION
                                if   $cp->{'last'}{'item_id'}      eq $item_id
                                &&   $cp->{'last'}{'action_id'}    == $action_id
                                &&   $time - $cp->{'last'}{'time'} <= DUBLICATE_ITEM_ID_THRESHOLD
                                && ! _item_id_is_unit($item_id)
                                ;

                            if (_item_id_is_hero($item_id)) {
                                $cp->{'heroes'}{$item_id} = {};
                                $cp->{'heroes_order'} //= [];
                                push @{ $cp->{'heroes_order'} }, $item_id;
                                _item_id_add_to_player_build_order($item_id, $cp, $time);
                            } elsif (_item_id_is_hero_ability($item_id)) {
                                my $hero_id = _item_id_unit_ability_get_hero($item_id);
                                $cp->{'heroes'}{$hero_id}{$item_id}++;
                            } elsif (_item_id_is_unit($item_id)) {
                                my $race = _item_id_unit_get_race($item_id);
                                if ($race eq 'creeps') {
                                    # Mercenaries, Shredders, Goblin Zeppelins and other passive units
                                    # are hired from neutral buildings. The player can select only one such
                                    # building at a time.
                                    $cp->{'race'}{$race}{'units'}{$item_id} += 1;
                                } else {
                                    # It's pretty hard to accurately count the number of units a player produces.
                                    # Because of how the selection information of buildings/units is stored in the replay.
                                    # When a player orders workers to build buildings we don't know what 'object_id' this building will have,
                                    # except if he selects the building alone (i.e only the building is selected by the player).
                                    # When a player Shift+Clicks on building(s) only their 'object_id' are "visible" not their "type" ('hbar', 'hfoo', etc.).
                                    # So if a player adds a widget (unit/building) to his selection via Shift+Click which he hasn't already selected alone
                                    # we don't know what he has added to his selection.
                                    # And if he starts the production of a unit we don't know by how much to increment.

                                    # We keep track of which buildings the player selects (i.e his selection).
                                    # The selection is a hash of { 'object_id's => 1, ... }, because the 'object_id's are unique.
                                    # When an action_select_subgroup happens we can detect the type of the selected unit and it's 'object_id[1|2]'.
                                    #
                                    my $number_of_units_to_be_produced = grep {
                                        my $object_id = $_;
                                        exists $cp->{'object_ids'}{$object_id}
                                            && $cp->{'object_ids'}{$object_id} eq $cp->{'last'}{'selected_building'};
                                    } keys %{ $cp->{'selection'} };

                                    # say $cp->{'last'}{'selected_building'};
                                    # use DDP; say p $cp->{'selection'};
                                    # exit 1;
                                    $cp->{'race'}{$race}{'units'}{$item_id} += $number_of_units_to_be_produced;
                                }

                                _item_id_add_to_player_build_order($item_id, $cp, $time);
                            } elsif (_item_id_is_building($item_id)) {
                                my $race = _item_id_building_get_race($item_id);
                                $cp->{'race'}{$race}{'buildings'}{$item_id}++;
                                _item_id_add_to_player_build_order($item_id, $cp, $time);
                            } elsif (_item_id_is_upgrade($item_id)) {
                                my $race = _item_id_upgrade_get_race($item_id);
                                $cp->{'race'}{$race}{'upgrades'}{$item_id}++;
                                _item_id_add_to_player_build_order($item_id, $cp, $time);
                            } else { # item_id is an "inventory item"
                                state $tinker_abilities_upgrades = [
                                    'ANs1', 'ANs2', 'ANs3', # Pocket Factory Upgrade 1|2|3
                                    'ANc1', 'ANc2', 'ANc3', # Cluster Rockets Upgrade 1|2|3
                                    'ANg1', 'ANg2', 'ANg3', # Robo-Goblin Upgrade 1|2|3
                                    'ANd1', 'ANd2', 'ANd3', # Demolish Upgrade 1|2|3
                                ];
                                # say "player_id: $player_id; unknown \$item_id: $item_id";
                                if (none { $item_id eq $_ } @$tinker_abilities_upgrades) {
                                    $cp->{'items'}{$item_id}++;
                                }
                            }

                            $cp->{'last'}{'item_id'} = $item_id;
                            $cp->{'last'}{'time'} = $time;
                        } else {
                            $item_id = _numerical_item_id_to_name($decimal_item_id);
                            # say "order_id: $item_id";
                            if ($item_id eq 'cancel') {
                                # say "\$item_id: $item_id", '; last_item_id: ', $cp->{'last'}{'item_id'};
                                my $item_id = $cp->{'last'}{'item_id'};
                                if (_item_id_is_hero($item_id)) {
                                    _item_id_undo_last_item_id_for_player($cp);

                                } elsif (_item_id_is_unit($item_id)) {
                                    my $race = _item_id_unit_get_race($item_id);
                                    my $number_of_units_to_remove_from_production = grep {
                                        my $object_id = $_;
                                        exists $cp->{'object_ids'}{$object_id}
                                            && $cp->{'object_ids'}{$object_id} eq $cp->{'last'}{'selected_building'};
                                    } keys %{ $cp->{'selection'} };

                                    $cp->{'race'}{$race}{'units'}{$item_id} -= $number_of_units_to_remove_from_production;
                                    delete $cp->{'race'}{$race}{'units'}{$item_id}
                                        if $cp->{'race'}{$race}{'units'}{$item_id} <= 0;
                                }
                            } elsif ($item_id =~ m/itemuse0[0-5]/) {
                                my $ability_flags = $action_block->{'action'}{'action_unit'}{'ability_flags'};
                                my $tome_of_retraining_another_check = $action_block->{'action'}{'action_unit'}{'unknown'};
                                $tome_of_retraining_another_check = $tome_of_retraining_another_check->{'unknown_a'} == $tome_of_retraining_another_check->{'unknown_b'};
                                # probably tome of retraining
                                if ($ability_flags == 64 && $tome_of_retraining_another_check) {
                                    # say 'probably tome of retraining';
                                    $cp->{'heroes'}{ $cp->{'last'}{'selected_hero'} } = {};
                                }
                            }
                        }
                    } elsif ($action_id == $action_change_selection_id) {
                        my $selection_mode = $action_block->{'action'}{'selection_mode'};
                        if ($selection_mode eq 'add_to_selection') {
                            my $unit_ids = $action_block->{'action'}{'object_id'};
                            $unit_ids = [ map { $_->{'object_id1'} } @$unit_ids ];
                            @{ $cp->{'selection'} }{@$unit_ids} = (1) x @$unit_ids;

                        } elsif ($selection_mode eq 'remove_from_selection') {
                            my $unit_ids = $action_block->{'action'}{'object_id'};
                            $unit_ids = [ map { $_->{'object_id1'} } @$unit_ids ];
                            delete @{ $cp->{'selection'} }{@$unit_ids};
                        }

                    } elsif ($action_id == $action_pre_subselection_id) {
                        $cp->{'last'}{'change_selection'} = $cp->{'last'}{'action'};
                        # use DDP; say p $cp->{'last'}{'change_selection'};

                    } elsif ($action_id == $action_select_subgroup_id) {
                        my $item_id = _decimal_to_string_encoded_item_id($action_block->{'action'}{'action_select_subgroup'}{'item_id'});

                        if (_item_id_is_hero($item_id)) {
                            # say "last selected hero: $item_id";
                            $cp->{'last'}{'selected_hero'} = $item_id;
                        } elsif (_item_id_is_building($item_id)) {
                            my $object_id = $action_block->{'action'}{'action_select_subgroup'}{'object_id1'};
                            $cp->{'object_ids'}{$object_id} = $item_id;
                            $cp->{'last'}{'selected_building'} = $item_id;

                            $object_id = $cp->{'last'}{'change_selection'}{'object_id'};
                            $object_id = [ map { $_->{'object_id1'} } @$object_id ];

                            # use DDP; say p $object_id;

                            @{ $cp->{'object_ids'} }{ @$object_id } = ($item_id) x @$object_id;
                            # use DDP; say p $cp->{'object_ids'};
                            # exit 1;
                        }
                    } elsif ($action_id == $action_assign_group_hotkey_id) {
                        my $hotkey = $action_block->{'action'}{'group_number'} + 1;
                        # $cp->{'hotkeys'}{$hotkey}{'assign'} //= 0;
                        $cp->{'hotkeys'}{$hotkey}{'assign'}++;
                        $cp->{'hotkeys'}{$hotkey}{'number_of_units_in_group'} = $action_block->{'action'}{'number_of_units_in_group'};
                        $cp->{'hotkeys'}{$hotkey}{'unit_ids'} = [ map { $_->{'object_id1'} } @{ $action_block->{'action'}{'group'} } ];

                    } elsif ($action_id == $action_select_group_hotkey_id) {
                        my $hotkey = $action_block->{'action'}{'group_number'} + 1;
                        # $cp->{'hotkeys'}{$hotkey}{'select'} //= 0;
                        $cp->{'hotkeys'}{$hotkey}{'select'}++;

                        my $unit_ids = $cp->{'hotkeys'}{$hotkey}{'unit_ids'};
                        $cp->{'selection'} = { map { $_ => 1 } @$unit_ids };
                    } elsif ($action_id == $action_remove_unit_from_building_queue_id) {
                        my $item_id = _decimal_to_string_encoded_item_id($action_block->{'action'}{'unit_id'});
                        my $race = _item_id_unit_get_race($item_id);
                        if ($race) {
                            $cp->{'race'}{$race}{'units'}{$item_id}--;
                            delete $cp->{'race'}{$race}{'units'}{$item_id}
                                if $cp->{'race'}{$race}{'units'}{$item_id} <= 0;
                        } else {
                            $race = _item_id_building_get_race($item_id);
                            if ($race) {
                                $cp->{'race'}{$race}{'buildings'}{$item_id}--;
                                delete $cp->{'race'}{$race}{'buildings'}{$item_id}
                                    if $cp->{'race'}{$race}{'buildings'}{$item_id} <= 0;
                            } else {
                                $race = _item_id_upgrade_get_race($item_id);
                                if ($race) {
                                    $cp->{'race'}{$race}{'upgrades'}{$item_id}--;
                                    delete $cp->{'race'}{$race}{'upgrades'}{$item_id}
                                        if $cp->{'race'}{$race}{'upgrades'}{$item_id} <= 0;
                                }
                            }
                        }
                    }
                    # elsif ($action_id == $action_esc_pressed_id) {
                        # _item_id_undo_last_item_id_for_player($cp);
                    # }
                } continue { # finally found a use for this construct...
                    $cp->{'last'}{'action_id'} = $action_id;
                    $cp->{'last'}{'action'}    = $action_block->{'action'};
                }
            }
        } elsif ($block_player_chat_message_id == $block->{'block_id'}) {
            my $chat_message = $block->{'block'};
            push @$chat, {
                time             => $time,
                sender_player_id => $chat_message->{'player_id'},
                recipient        => $chat_message->{'recipient'},
                text             => $chat_message->{'message'},
                type             => $chat_message->{'type'},
            };
        } elsif ($block_leave_game_id == $block->{'block_id'}) {
            $players->{$block->{'block'}{'player_id'}}{'left_at'} = $time;
            push @leave_game_blocks, $block->{'block'};
        }
    }

    # use DDP; say p $chat;
    _players_calculate_game_result($players, \@leave_game_blocks);

    ($players, $chat, $time);
} # It's not that fucking big.

sub _item_id_undo_last_item_id_for_player { my ($player) = @_;
    my $last_item_id = $player->{'last'}{'item_id'};
    if (_item_id_is_hero($last_item_id)) {
        delete $player->{'heroes'}{$last_item_id};
    }
    delete $player->{'build_order'}->{ $player->{'last'}{'time'} };
}

sub _item_id_add_to_player_build_order { my ($item_id, $player, $time) = @_;
    # push @{ $player->{'build_order'} }, { time => $time, item_id => $item_id };
    $player->{'build_order'}->{$time} = { item_id => $item_id };
}


# Most of the names come from cJass's lib/cj_order.j v 0.12
# by Shadow Daemon \\ cjass.xgm.ru
sub _numerical_item_id_to_name { my ($numerical_item_id) = @_;
    state $map = {
        851971 => 'smart',
        851972 => 'stop',
        851976 => 'cancel', # cancel (train, research)
        851980 => 'setrally',
        851981 => 'getitem',
        851983 => 'attack',
        851984 => 'attackground',
        851985 => 'attackonce',
        851986 => 'move',
        851988 => 'AImove',
        851990 => 'patrol',
        851993 => 'holdposition',
        851994 => 'build',
        851995 => 'humanbuild',
        851996 => 'orcbuild',
        851997 => 'nightelfbuild',
        851998 => 'undeadbuild',
        851999 => 'resumebuild',
        852001 => 'dropitem',
        852002 => 'itemdrag00',
        852003 => 'itemdrag01',
        852004 => 'itemdrag02',
        852005 => 'itemdrag03',
        852006 => 'itemdrag04',
        852007 => 'itemdrag05',
        852008 => 'itemuse00',
        852009 => 'itemuse01',
        852010 => 'itemuse02',
        852011 => 'itemuse03',
        852012 => 'itemuse04',
        852013 => 'itemuse05',
        852015 => 'detectaoe',
        852017 => 'resumeharvesting',
        852018 => 'harvest',
        852020 => 'returnresources',
        852021 => 'autoharvestgold',
        852022 => 'autoharvestlumber',
        852023 => 'neutraldetectaoe',
        852024 => 'repair',
        852025 => 'repairon',
        852026 => 'repairoff',
        852027 => 'revivehero01',
        852028 => 'revivehero02',
        852029 => 'revivehero03',
        852030 => 'revivehero04',
        852031 => 'revivehero05',
        # 852032 => 'revivehero07',
        # 852033 => 'revivehero08',
        # 852034 => 'revivehero09',
        # 852035 => 'revivehero10',
        # 852036 => 'revivehero11',
        # 852037 => 'revivehero12',
        # 852038 => 'revivehero13',
        852039 => 'revive',
        852040 => 'selfdestruct',
        852041 => 'selfdestructon',
        852042 => 'selfdestructoff',
        852043 => 'board',
        852044 => 'forceboard',
        852046 => 'load',
        852047 => 'unload',
        852048 => 'unloadall',
        852049 => 'unloadallinstant',
        852050 => 'loadcorpse',
        852051 => 'loadcorpseon',
        852052 => 'loadcorpseoff',
        852053 => 'loadcorpseinstant',
        852054 => 'unloadallcorpses',
        852055 => 'defend',
        852056 => 'undefend',
        852057 => 'dispel',
        852060 => 'flare',
        852063 => 'heal',
        852064 => 'healon',
        852065 => 'healoff',
        852066 => 'innerfire',
        852067 => 'innerfireon',
        852068 => 'innerfireoff',
        852069 => 'invisibility',
        852071 => 'militiaconvert',
        852072 => 'militia',
        852073 => 'militiaoff',
        852074 => 'polymorph',
        852075 => 'slow',
        852076 => 'slowon',
        852077 => 'slowoff',
        852079 => 'tankdroppilot',
        852080 => 'tankloadpilot',
        852081 => 'tankpilot',
        852082 => 'townbellon',
        852083 => 'townbelloff',
        852086 => 'avatar',
        852087 => 'unavatar',
        852089 => 'blizzard',
        852090 => 'divineshield',
        852091 => 'undivineshield',
        852092 => 'holybolt',
        852093 => 'massteleport',
        852094 => 'resurrection',
        852095 => 'thunderbolt',
        852096 => 'thunderclap',
        852097 => 'waterelemental',
        852099 => 'battlestations',
        852100 => 'berserk',
        852101 => 'bloodlust',
        852102 => 'bloodluston',
        852103 => 'bloodlustoff',
        852104 => 'devour',
        852105 => 'evileye',
        852106 => 'ensnare',
        852107 => 'ensnareon',
        852108 => 'ensnareoff',
        852109 => 'healingward',
        852110 => 'lightningshield',
        852111 => 'purge',
        852113 => 'standdown',
        852114 => 'stasistrap',
        852119 => 'chainlightning',
        852121 => 'earthquake',
        852122 => 'farsight',
        852123 => 'mirrorimage',
        852125 => 'shockwave',
        852126 => 'spiritwolf',
        852127 => 'stomp',
        852128 => 'whirlwind',
        852129 => 'windwalk',
        852130 => 'unwindwalk',
        852131 => 'ambush',
        852132 => 'autodispel',
        852133 => 'autodispelon',
        852134 => 'autodispeloff',
        852135 => 'barkskin',
        852136 => 'barkskinon',
        852137 => 'barkskinoff',
        852138 => 'bearform',
        852139 => 'unbearform',
        852140 => 'corrosivebreath',
        852142 => 'loadarcher',
        852143 => 'mounthippogryph',
        852144 => 'cyclone',
        852145 => 'detonate',
        852146 => 'eattree',
        852147 => 'entangle',
        852148 => 'entangleinstant',
        852149 => 'faeriefire',
        852150 => 'faeriefireon',
        852151 => 'faeriefireoff',
        852155 => 'ravenform',
        852156 => 'unravenform',
        852157 => 'recharge',
        852158 => 'rechargeon',
        852159 => 'rechargeoff',
        852160 => 'rejuvination',
        852161 => 'renew',
        852162 => 'renewon',
        852163 => 'renewoff',
        852164 => 'roar',
        852165 => 'root',
        852166 => 'unroot',
        852171 => 'entanglingroots',
        852173 => 'flamingarrowstarg',
        852174 => 'flamingarrows',
        852175 => 'unflamingarrows',
        852176 => 'forceofnature',
        852177 => 'immolation',
        852178 => 'unimmolation',
        852179 => 'manaburn',
        852180 => 'metamorphosis',
        852181 => 'scout',
        852182 => 'sentinel',
        852183 => 'starfall',
        852184 => 'tranquility',
        852185 => 'acolyteharvest',
        852186 => 'antimagicshell',
        852187 => 'blight',
        852188 => 'cannibalize',
        852189 => 'cripple',
        852190 => 'curse',
        852191 => 'curseon',
        852192 => 'curseoff',
        852195 => 'freezingbreath',
        852196 => 'possession',
        852197 => 'raisedead',
        852198 => 'raisedeadon',
        852199 => 'raisedeadoff',
        852200 => 'instant',
        852201 => 'requestsacrifice',
        852202 => 'restoration',
        852203 => 'restorationon',
        852204 => 'restorationoff',
        852205 => 'sacrifice',
        852206 => 'stoneform',
        852207 => 'unstoneform',
        852209 => 'unholyfrenzy',
        852210 => 'unsummon',
        852211 => 'web',
        852212 => 'webon',
        852213 => 'weboff',
        852214 => 'wispharvest',
        852215 => 'auraunholy',
        852216 => 'auravampiric',
        852217 => 'animatedead',
        852218 => 'carrionswarm',
        852219 => 'darkritual',
        852220 => 'darksummoning',
        852221 => 'deathanddecay',
        852222 => 'deathcoil',
        852223 => 'deathpact',
        852224 => 'dreadlordinferno',
        852225 => 'frostarmor',
        852226 => 'frostnova',
        852227 => 'sleep',
        852228 => 'darkconversion',
        852229 => 'darkportal',
        852230 => 'fingerofdeath',
        852231 => 'firebolt',
        852232 => 'inferno',
        852233 => 'gold2lumber',
        852234 => 'lumber2gold',
        852235 => 'spies',
        852237 => 'rainofchaos',
        852238 => 'rainoffire',
        852239 => 'request_hero',
        852240 => 'disassociate',
        852241 => 'revenge',
        852242 => 'soulpreservation',
        852243 => 'coldarrowstarg',
        852244 => 'coldarrows',
        852245 => 'uncoldarrows',
        852246 => 'creepanimatedead',
        852247 => 'creepdevour',
        852248 => 'creepheal',
        852249 => 'creephealon',
        852250 => 'creephealoff',
        852252 => 'creepthunderbolt',
        852253 => 'creepthunderclap',
        852254 => 'poisonarrowstarg',
        852255 => 'poisonarrows',
        852256 => 'unpoisonarrows',
        852270 => 'reveal', # human arcane tower
        852458 => 'frostarmoron',
        852459 => 'frostarmoroff',
        852462 => 'awaken00',
        852463 => 'awaken01',
        852464 => 'awaken02',
        852465 => 'awaken03',
        852466 => 'awaken04', # 'awaken',
        852467 => 'nagabuild',
        852469 => 'mount',
        852470 => 'dismount',
        852473 => 'cloudoffog',
        852474 => 'controlmagic',
        852478 => 'magicdefense',
        852479 => 'magicundefense',
        852480 => 'magicleash',
        852481 => 'phoenixfire',
        852482 => 'phoenixmorph',
        852483 => 'spellsteal',
        852484 => 'spellstealon',
        852485 => 'spellstealoff',
        852486 => 'banish',
        852487 => 'drain',
        852488 => 'flamestrike',
        852489 => 'summonphoenix',
        852490 => 'ancestralspirit',
        852491 => 'ancestralspirittarget',
        852493 => 'corporealform',
        852494 => 'uncorporealform',
        852495 => 'disenchant',
        852496 => 'etherealform',
        852497 => 'unetherealform',
        852499 => 'spiritlink',
        852500 => 'unstableconcoction',
        852501 => 'healingwave',
        852502 => 'hex',
        852503 => 'voodoo',
        852504 => 'ward',
        852505 => 'autoentangle',
        852506 => 'autoentangleinstant',
        852507 => 'coupletarget',
        852508 => 'coupleinstant',
        852509 => 'decouple',
        852511 => 'grabtree',
        852512 => 'manaflareon',
        852513 => 'manaflareoff',
        852514 => 'phaseshift',
        852515 => 'phaseshifton',
        852516 => 'phaseshiftoff',
        852517 => 'phaseshiftinstant',
        852520 => 'taunt',
        852521 => 'vengeance',
        852522 => 'vengeanceon',
        852523 => 'vengeanceoff',
        852524 => 'vengeanceinstant',
        852525 => 'blink',
        852526 => 'fanofknives',
        852527 => 'shadowstrike',
        852528 => 'spiritofvengeance',
        852529 => 'absorb',
        852531 => 'avengerform',
        852532 => 'unavengerform',
        852533 => 'burrow',
        852534 => 'unburrow',
        852536 => 'devourmagic',
        852539 => 'flamingattacktarg',
        852540 => 'flamingattack',
        852541 => 'unflamingattack',
        852542 => 'replenish',
        852543 => 'replenishon',
        852544 => 'replenishoff',
        852545 => 'replenishlife',
        852546 => 'replenishlifeon',
        852547 => 'replenishlifeoff',
        852548 => 'replenishmana',
        852549 => 'replenishmanaon',
        852550 => 'replenishmanaoff',
        852551 => 'carrionscarabs',
        852552 => 'carrionscarabson',
        852553 => 'carrionscarabsoff',
        852554 => 'carrionscarabsinstant',
        852555 => 'impale',
        852556 => 'locustswarm',
        852560 => 'breathoffrost',
        852561 => 'frenzy',
        852562 => 'frenzyon',
        852563 => 'frenzyoff',
        852564 => 'mechanicalcritter',
        852565 => 'mindrot',
        852566 => 'neutralinteract', # change shop buyer
        852568 => 'preservation',
        852569 => 'sanctuary',
        852570 => 'shadowsight',
        852571 => 'spellshield',
        852572 => 'spellshieldaoe',
        852573 => 'spirittroll',
        852574 => 'steal',
        852576 => 'attributemodskill',
        852577 => 'blackarrow',
        852578 => 'blackarrowon',
        852579 => 'blackarrowoff',
        852580 => 'breathoffire',
        852581 => 'charm',
        852583 => 'doom',
        852585 => 'drunkenhaze',
        852586 => 'elementalfury',
        852587 => 'forkedlightning',
        852588 => 'howlofterror',
        852589 => 'manashieldon',
        852590 => 'manashieldoff',
        852591 => 'monsoon',
        852592 => 'silence',
        852593 => 'stampede',
        852594 => 'summongrizzly',
        852595 => 'summonquillbeast',
        852596 => 'summonwareagle',
        852597 => 'tornado',
        852598 => 'wateryminion',
        852599 => 'battleroar',
        852600 => 'channel',
        852601 => 'parasite',
        852602 => 'parasiteon',
        852603 => 'parasiteoff',
        852604 => 'submerge',
        852605 => 'unsubmerge',
        852630 => 'neutralspell',
        852651 => 'militiaunconvert',
        852652 => 'clusterrockets',
        852656 => 'robogoblin',
        852657 => 'unrobogoblin',
        852658 => 'summonfactory',
        852662 => 'acidbomb',
        852663 => 'chemicalrage',
        852664 => 'healingspray',
        852665 => 'transmute',
        852667 => 'lavamonster',
        852668 => 'soulburn',
        852669 => 'volcano',
        852670 => 'incineratearrow',
        852671 => 'incineratearrowon',
        852672 => 'incineratearrowoff',
    };
    $map->{$numerical_item_id};
}

sub _decimal_to_string_encoded_item_id { my ($decimal) = @_;
    scalar reverse pack 'V', $decimal
}

# say _item_id_is_hero('Obla');
# say _item_id_is_hero('hfoo');
# say _item_id_is_hero('hhou');
sub _item_id_is_hero { my ($item_id) = @_;
    _item_id_is_unit_type_from_race($item_id, 'heroes', 'human')
 || _item_id_is_unit_type_from_race($item_id, 'heroes', 'orc')
 || _item_id_is_unit_type_from_race($item_id, 'heroes', 'undead')
 || _item_id_is_unit_type_from_race($item_id, 'heroes', 'nightelf')
 || _item_id_is_unit_type_from_race($item_id, 'heroes', 'creeps')
}

# say _item_id_hero_get_race('Hamg');
# say _item_id_hero_get_race('Obla');
# say _item_id_hero_get_race('Ulic');
# say _item_id_hero_get_race('Eill');
# say _item_id_hero_get_race('Ntin');
# say _item_id_hero_get_race('hfoo');
sub _item_id_hero_get_race { my ($hero) = @_;
    my $units = _item_id_units();
    return 'human' if $units->{'human'}{'heroes'}{$hero};
    return 'orc' if $units->{'orc'}{'heroes'}{$hero};
    return 'undead' if $units->{'undead'}{'heroes'}{$hero};
    return 'nightelf' if $units->{'nightelf'}{'heroes'}{$hero};
    return 'creeps' if $units->{'creeps'}{'heroes'}{$hero};
    # return 'hero_unknown_race';
}

# say _item_id_is_unit('Obla');
# say _item_id_is_unit('hfoo');
# say _item_id_is_unit('hhou');
sub _item_id_is_unit { my ($item_id) = @_;
    _item_id_is_unit_type_from_race($item_id, 'units', 'human')
 || _item_id_is_unit_type_from_race($item_id, 'units', 'orc')
 || _item_id_is_unit_type_from_race($item_id, 'units', 'undead')
 || _item_id_is_unit_type_from_race($item_id, 'units', 'nightelf')
 || _item_id_is_unit_type_from_race($item_id, 'units', 'creeps')
 # || _item_id_is_unit_type_from_race($item_id, 'units', 'demon')
}

# say _item_id_unit_get_race('hfoo');
# say _item_id_unit_get_race('opeo');
# say _item_id_unit_get_race('ugho');
# say _item_id_unit_get_race('emtg');
# say _item_id_unit_get_race('nitp');
sub _item_id_unit_get_race { my ($unit) = @_;
    my $units = _item_id_units();
    return 'human' if $units->{'human'}{'units'}{$unit};
    return 'orc' if $units->{'orc'}{'units'}{$unit};
    return 'undead' if $units->{'undead'}{'units'}{$unit};
    return 'nightelf' if $units->{'nightelf'}{'units'}{$unit};
    return 'creeps' if $units->{'creeps'}{'units'}{$unit};
    # return 'demon' if $units->{'demon'}{'units'}{$unit};
    # return 'unit_unknown_race';
}

# say _item_id_is_building('Obla');
# say _item_id_is_building('hfoo');
# say _item_id_is_building('hhou');
sub _item_id_is_building { my ($item_id) = @_;
    _item_id_is_unit_type_from_race($item_id, 'buildings', 'human')
 || _item_id_is_unit_type_from_race($item_id, 'buildings', 'orc')
 || _item_id_is_unit_type_from_race($item_id, 'buildings', 'undead')
 || _item_id_is_unit_type_from_race($item_id, 'buildings', 'nightelf')
 || _item_id_is_unit_type_from_race($item_id, 'buildings', 'creeps')
 # || _item_id_is_unit_type_from_race($item_id, 'buildings', 'demon')
}

# say _item_id_building_get_race('hhou');
# say _item_id_building_get_race('otrb');
# say _item_id_building_get_race('uzig');
# say _item_id_building_get_race('emow');
# say _item_id_building_get_race('nfgo');
sub _item_id_building_get_race { my ($building) = @_;
    my $units = _item_id_units();
    return 'human' if $units->{'human'}{'buildings'}{$building};
    return 'orc' if $units->{'orc'}{'buildings'}{$building};
    return 'undead' if $units->{'undead'}{'buildings'}{$building};
    return 'nightelf' if $units->{'nightelf'}{'buildings'}{$building};
    return 'creeps' if $units->{'creeps'}{'buildings'}{$building};
    # return 'demon' if $units->{'demon'}{'buildings'}{$building};
    # return 'building_unknown_race';
}

sub _item_id_is_unit_type_from_race { my ($item_id, $unit_type, $race) = @_;
    my $units = _item_id_units();
    defined $units->{$race}{$unit_type}{$item_id};
}

sub _item_id_units {
    state $units =
{
  commoner => {
                units => { nvil => 1, nvk2 => 1, nvl2 => 1, nvlk => 1, nvlw => 1 },
              },
  creeps   => {
                buildings => { nfgo => 1 },
                heroes    => {
                               Naka => 1,
                               Nal2 => 1,
                               Nal3 => 1,
                               Nalc => 1,
                               Nalm => 1,
                               Nbrn => 1,
                               Nbst => 1,
                               Nfir => 1,
                               Nngs => 1,
                               Npbm => 1,
                               Nplh => 1,
                               Nrob => 1,
                               Ntin => 1,
                             },
                units     => {
                               nadk => 1,
                               nadr => 1,
                               nadw => 1,
                               nahy => 1,
                               nanb => 1,
                               nanc => 1,
                               nane => 1,
                               nanm => 1,
                               nano => 1,
                               nanw => 1,
                               narg => 1,
                               nass => 1,
                               nban => 1,
                               nbda => 1,
                               nbdk => 1,
                               nbdm => 1,
                               nbdo => 1,
                               nbdr => 1,
                               nbds => 1,
                               nbdw => 1,
                               nbld => 1,
                               nbnb => 1,
                               nbot => 1,
                               nbrg => 1,
                               nbwm => 1,
                               nbzd => 1,
                               nbzk => 1,
                               nbzw => 1,
                               ncat => 1,
                               ncea => 1,
                               ncen => 1,
                               ncer => 1,
                               ncfs => 1,
                               ncim => 1,
                               ncks => 1,
                               ncnk => 1,
                               ndmu => 1,
                               ndqn => 1,
                               ndqp => 1,
                               ndqs => 1,
                               ndqt => 1,
                               ndqv => 1,
                               ndrd => 1,
                               ndrf => 1,
                               ndrh => 1,
                               ndrj => 1,
                               ndrl => 1,
                               ndrm => 1,
                               ndrn => 1,
                               ndrp => 1,
                               ndrs => 1,
                               ndrt => 1,
                               ndrv => 1,
                               ndrw => 1,
                               ndsa => 1,
                               ndtb => 1,
                               ndth => 1,
                               ndtp => 1,
                               ndtr => 1,
                               ndtt => 1,
                               ndtw => 1,
                               nehy => 1,
                               nelb => 1,
                               nele => 1,
                               nenc => 1,
                               nenf => 1,
                               nenp => 1,
                               nepl => 1,
                               nerd => 1,
                               ners => 1,
                               nerw => 1,
                               nfgb => 1,
                               nfgl => 1,
                               nfgt => 1,
                               nfgu => 1,
                               nfod => 1,
                               nfor => 1,
                               nfot => 1,
                               nfov => 1,
                               nfpc => 1,
                               nfpe => 1,
                               nfpl => 1,
                               nfps => 1,
                               nfpt => 1,
                               nfpu => 1,
                               nfra => 1,
                               nfrb => 1,
                               nfre => 1,
                               nfrg => 1,
                               nfrl => 1,
                               nfrp => 1,
                               nfrs => 1,
                               nfsh => 1,
                               nfsp => 1,
                               nftb => 1,
                               nftk => 1,
                               nftr => 1,
                               nftt => 1,
                               ngdk => 1,
                               nggr => 1,
                               ngh1 => 1,
                               ngh2 => 1,
                               ngir => 1,
                               nglm => 1,
                               ngna => 1,
                               ngnb => 1,
                               ngno => 1,
                               ngns => 1,
                               ngnv => 1,
                               ngnw => 1,
                               ngrd => 1,
                               ngrk => 1,
                               ngrw => 1,
                               ngsp => 1,
                               ngst => 1,
                               ngz1 => 1,
                               ngz2 => 1,
                               ngz3 => 1,
                               nhar => 1,
                               nhdc => 1,
                               nhfp => 1,
                               nhhr => 1,
                               nhrh => 1,
                               nhrq => 1,
                               nhrr => 1,
                               nhrw => 1,
                               nhyd => 1,
                               nhyh => 1,
                               nina => 1,
                               ninc => 1,
                               ninm => 1,
                               nith => 1,
                               nitp => 1,
                               nitr => 1,
                               nits => 1,
                               nitt => 1,
                               nitw => 1,
                               njg1 => 1,
                               njga => 1,
                               njgb => 1,
                               nkob => 1,
                               nkog => 1,
                               nkol => 1,
                               nkot => 1,
                               nlds => 1,
                               nlkl => 1,
                               nlpd => 1,
                               nlpr => 1,
                               nlps => 1,
                               nlrv => 1,
                               nlsn => 1,
                               nltc => 1,
                               nltl => 1,
                               nlur => 1,
                               nmam => 1,
                               nmbg => 1,
                               nmcf => 1,
                               nmdr => 1,
                               nmfs => 1,
                               nmgd => 1,
                               nmgr => 1,
                               nmgw => 1,
                               nmit => 1,
                               nmmu => 1,
                               nmpg => 1,
                               nmrl => 1,
                               nmrm => 1,
                               nmrr => 1,
                               nmrv => 1,
                               nmsc => 1,
                               nmsn => 1,
                               nmtw => 1,
                               nndk => 1,
                               nndr => 1,
                               nnht => 1,
                               nnwa => 1,
                               nnwl => 1,
                               nnwq => 1,
                               nnwr => 1,
                               nnws => 1,
                               noga => 1,
                               nogl => 1,
                               nogm => 1,
                               nogn => 1,
                               nogo => 1,
                               nogr => 1,
                               nomg => 1,
                               nowb => 1,
                               nowe => 1,
                               nowk => 1,
                               npfl => 1,
                               npfm => 1,
                               nplb => 1,
                               nplg => 1,
                               npn1 => 1,
                               npn2 => 1,
                               npn3 => 1,
                               npn4 => 1,
                               npn5 => 1,
                               npn6 => 1,
                               nqbh => 1,
                               nrdk => 1,
                               nrdr => 1,
                               nrel => 1,
                               nrog => 1,
                               nrvd => 1,
                               nrvf => 1,
                               nrvi => 1,
                               nrvl => 1,
                               nrvs => 1,
                               nrwm => 1,
                               nrzb => 1,
                               nrzg => 1,
                               nrzm => 1,
                               nrzs => 1,
                               nrzt => 1,
                               nsat => 1,
                               nsbm => 1,
                               nsc2 => 1,
                               nsc3 => 1,
                               nsca => 1,
                               nscb => 1,
                               nsce => 1,
                               nsel => 1,
                               nsgb => 1,
                               nsgg => 1,
                               nsgh => 1,
                               nsgn => 1,
                               nsgt => 1,
                               nska => 1,
                               nske => 1,
                               nskf => 1,
                               nskg => 1,
                               nskm => 1,
                               nsko => 1,
                               nslf => 1,
                               nslh => 1,
                               nsll => 1,
                               nslm => 1,
                               nsln => 1,
                               nslr => 1,
                               nslv => 1,
                               nsns => 1,
                               nsoc => 1,
                               nsog => 1,
                               nspb => 1,
                               nspd => 1,
                               nspg => 1,
                               nspp => 1,
                               nspr => 1,
                               nsqa => 1,
                               nsqe => 1,
                               nsqo => 1,
                               nsqt => 1,
                               nsra => 1,
                               nsrh => 1,
                               nsrn => 1,
                               nsrv => 1,
                               nsrw => 1,
                               nssp => 1,
                               nsth => 1,
                               nstl => 1,
                               nsts => 1,
                               nstw => 1,
                               nsty => 1,
                               nsw1 => 1,
                               nsw2 => 1,
                               nsw3 => 1,
                               nthl => 1,
                               ntka => 1,
                               ntkc => 1,
                               ntkf => 1,
                               ntkh => 1,
                               ntks => 1,
                               ntkt => 1,
                               ntkw => 1,
                               ntrd => 1,
                               ntrg => 1,
                               ntrh => 1,
                               ntrs => 1,
                               ntrt => 1,
                               ntrv => 1,
                               ntws => 1,
                               nubk => 1,
                               nubr => 1,
                               nubw => 1,
                               nvde => 1,
                               nvdg => 1,
                               nvdl => 1,
                               nvdw => 1,
                               nwen => 1,
                               nwiz => 1,
                               nwld => 1,
                               nwlg => 1,
                               nwlt => 1,
                               nwna => 1,
                               nwnr => 1,
                               nwns => 1,
                               nwrg => 1,
                               nwwd => 1,
                               nwwf => 1,
                               nwwg => 1,
                               nwzd => 1,
                               nwzg => 1,
                               nwzr => 1,
                               nzep => 1,
                             },
              },
  critters => {
                units => {
                  nalb => 1,
                  ncrb => 1,
                  nder => 1,
                  ndog => 1,
                  ndwm => 1,
                  nech => 1,
                  necr => 1,
                  nfbr => 1,
                  nfro => 1,
                  nhmc => 1,
                  npig => 1,
                  npng => 1,
                  npnw => 1,
                  nrac => 1,
                  nrat => 1,
                  nsea => 1,
                  nsha => 1,
                  nshe => 1,
                  nshf => 1,
                  nshw => 1,
                  nskk => 1,
                  nsno => 1,
                  nvul => 1,
                },
              },
  demon    => {
                buildings => { ncmw => 1 },
                units => { nba2 => 1, nbal => 1, nfel => 1, ninf => 1 },
              },
  human    => {
                buildings => {
                               halt => 1,
                               harm => 1,
                               haro => 1,
                               hars => 1,
                               hatw => 1,
                               hbar => 1,
                               hbla => 1,
                               hcas => 1,
                               hctw => 1,
                               hgra => 1,
                               hgtw => 1,
                               hhou => 1,
                               hkee => 1,
                               hlum => 1,
                               hshy => 1,
                               htow => 1,
                               hvlt => 1,
                               hwtw => 1,
                               nbt1 => 1,
                               nbt2 => 1,
                               ndgt => 1,
                               ndt1 => 1,
                               ndt2 => 1,
                               nef0 => 1,
                               nef1 => 1,
                               nef2 => 1,
                               nef3 => 1,
                               nef4 => 1,
                               nef5 => 1,
                               nef6 => 1,
                               nef7 => 1,
                               nefm => 1,
                               negf => 1,
                               negm => 1,
                               negt => 1,
                               net1 => 1,
                               net2 => 1,
                               nfrt => 1,
                               nft1 => 1,
                               nft2 => 1,
                               ngwr => 1,
                               nheb => 1,
                               nitb => 1,
                               nmgv => 1,
                               ntt1 => 1,
                               ntx2 => 1,
                             },
                heroes    => {
                               Hamg => 1,
                               Hant => 1,
                               Hapm => 1,
                               Harf => 1,
                               Hart => 1,
                               Hblm => 1,
                               Hdgo => 1,
                               Hgam => 1,
                               Hhkl => 1,
                               Hjai => 1,
                               Hkal => 1,
                               Hlgr => 1,
                               Hmbr => 1,
                               Hmgd => 1,
                               Hmkg => 1,
                               Hpal => 1,
                               Hpb1 => 1,
                               Hpb2 => 1,
                               Huth => 1,
                               Hvwd => 1,
                             },
                units     => {
                               hbew => 1,
                               hbot => 1,
                               hbsh => 1,
                               hcth => 1,
                               hdes => 1,
                               hdhw => 1,
                               hfoo => 1,
                               hgry => 1,
                               hgyr => 1,
                               hhdl => 1,
                               hhes => 1,
                               hkni => 1,
                               hmil => 1,
                               hmpr => 1,
                               hmtm => 1,
                               hmtt => 1,
                               hpea => 1,
                               hphx => 1,
                               hprt => 1,
                               hpxe => 1,
                               hrdh => 1,
                               hrif => 1,
                               hrtt => 1,
                               hsor => 1,
                               hspt => 1,
                               hwat => 1,
                               hwt2 => 1,
                               hwt3 => 1,
                               nbee => 1,
                               nbel => 1,
                               nchp => 1,
                               nemi => 1,
                               nhea => 1,
                               nhef => 1,
                               nhem => 1,
                               nhew => 1,
                               nhym => 1,
                               njks => 1,
                               nmdm => 1,
                               nmed => 1,
                               nser => 1,
                               nws1 => 1,
                             },
              },
  naga     => {
                buildings => { nnad => 1, nnfm => 1, nnsa => 1, nnsg => 1, nntg => 1, nntt => 1 },
                heroes    => { Hvsh => 1 },
                units     => {
                               nhyc => 1,
                               nmpe => 1,
                               nmyr => 1,
                               nmys => 1,
                               nnmg => 1,
                               nnrg => 1,
                               nnrs => 1,
                               nnsu => 1,
                               nnsw => 1,
                               nsbs => 1,
                               nsnp => 1,
                               nwgs => 1,
                             },
              },
  nightelf => {
                buildings => {
                               eaoe => 1,
                               eaom => 1,
                               eaow => 1,
                               eate => 1,
                               eden => 1,
                               edob => 1,
                               edos => 1,
                               egol => 1,
                               emow => 1,
                               eshy => 1,
                               etoa => 1,
                               etoe => 1,
                               etol => 1,
                               etrp => 1,
                               nbwd => 1,
                               ncap => 1,
                               ncaw => 1,
                               ncta => 1,
                               ncte => 1,
                               nctl => 1,
                               nfnp => 1,
                               nfv0 => 1,
                               nfv1 => 1,
                               nfv2 => 1,
                               nfv3 => 1,
                               nfv4 => 1,
                               ngob => 1,
                               nhcn => 1,
                               nvr0 => 1,
                               nvr1 => 1,
                               nvr2 => 1,
                             },
                heroes    => {
                               Ecen => 1,
                               Edem => 1,
                               Edmm => 1,
                               Eevi => 1,
                               Eevm => 1,
                               Efur => 1,
                               Eidm => 1,
                               Eill => 1,
                               Eilm => 1,
                               Ekee => 1,
                               Ekgg => 1,
                               Emfr => 1,
                               Emns => 1,
                               Emoo => 1,
                               Etyr => 1,
                               Ewar => 1,
                               Ewrd => 1,
                             },
                units     => {
                               earc => 1,
                               ebal => 1,
                               ebsh => 1,
                               echm => 1,
                               edcm => 1,
                               edes => 1,
                               edoc => 1,
                               edot => 1,
                               edry => 1,
                               edtm => 1,
                               efdr => 1,
                               efon => 1,
                               ehip => 1,
                               ehpr => 1,
                               eilw => 1,
                               emtg => 1,
                               enec => 1,
                               ensh => 1,
                               esen => 1,
                               eshd => 1,
                               espv => 1,
                               etrs => 1,
                               even => 1,
                               ewsp => 1,
                               now2 => 1,
                               now3 => 1,
                               nowl => 1,
                               nssn => 1,
                               nthr => 1,
                               nwat => 1,
                             },
              },
  orc      => {
                buildings => {
                               nbfl => 1,
                               ndfl => 1,
                               ndrb => 1,
                               npgf => 1,
                               npgr => 1,
                               nwc1 => 1,
                               nwc2 => 1,
                               oalt => 1,
                               obar => 1,
                               obea => 1,
                               ocbw => 1,
                               ofor => 1,
                               ofrt => 1,
                               ogre => 1,
                               oshy => 1,
                               osld => 1,
                               ostr => 1,
                               otrb => 1,
                               otto => 1,
                               ovln => 1,
                               owtw => 1,
                             },
                heroes    => {
                               Nbbc => 1,
                               Nsjs => 1,
                               Obla => 1,
                               Ocb2 => 1,
                               Ocbh => 1,
                               Odrt => 1,
                               Ofar => 1,
                               Ogld => 1,
                               Ogrh => 1,
                               Opgh => 1,
                               Orex => 1,
                               Orkn => 1,
                               Osam => 1,
                               Oshd => 1,
                               Otcc => 1,
                               Otch => 1,
                               Othr => 1,
                             },
                units     => {
                               nchg => 1,
                               nchr => 1,
                               nchw => 1,
                               nckb => 1,
                               ncpn => 1,
                               negz => 1,
                               ngbl => 1,
                               nmsh => 1,
                               nspc => 1,
                               nw2w => 1,
                               nwad => 1,
                               obot => 1,
                               ocat => 1,
                               odes => 1,
                               odkt => 1,
                               odoc => 1,
                               oeye => 1,
                               ogrk => 1,
                               ogru => 1,
                               ohun => 1,
                               ohwd => 1,
                               ojgn => 1,
                               okod => 1,
                               omtg => 1,
                               onzg => 1,
                               oosc => 1,
                               opeo => 1,
                               orai => 1,
                               oshm => 1,
                               osp1 => 1,
                               osp2 => 1,
                               osp3 => 1,
                               osp4 => 1,
                               ospm => 1,
                               ospw => 1,
                               osw1 => 1,
                               osw2 => 1,
                               osw3 => 1,
                               oswy => 1,
                               otau => 1,
                               otbk => 1,
                               otbr => 1,
                               otot => 1,
                               ovlj => 1,
                               owar => 1,
                               ownr => 1,
                               owyv => 1,
                             },
              },
  other    => {
                buildings => {
                  nbse => 1,
                  nbsw => 1,
                  ncb0 => 1,
                  ncb1 => 1,
                  ncb2 => 1,
                  ncb3 => 1,
                  ncb4 => 1,
                  ncb5 => 1,
                  ncb6 => 1,
                  ncb7 => 1,
                  ncb8 => 1,
                  ncb9 => 1,
                  ncba => 1,
                  ncbb => 1,
                  ncbc => 1,
                  ncbd => 1,
                  ncbe => 1,
                  ncbf => 1,
                  ncnt => 1,
                  ncop => 1,
                  ncp2 => 1,
                  ncp3 => 1,
                  nct1 => 1,
                  nct2 => 1,
                  ndch => 1,
                  ndh0 => 1,
                  ndh1 => 1,
                  ndh2 => 1,
                  ndh3 => 1,
                  ndh4 => 1,
                  ndke => 1,
                  ndkw => 1,
                  ndrg => 1,
                  ndrk => 1,
                  ndro => 1,
                  ndrr => 1,
                  ndru => 1,
                  ndrz => 1,
                  nfa1 => 1,
                  nfa2 => 1,
                  nfac => 1,
                  nfh0 => 1,
                  nfh1 => 1,
                  nfoh => 1,
                  nfr1 => 1,
                  nfr2 => 1,
                  ngad => 1,
                  ngme => 1,
                  ngnh => 1,
                  ngol => 1,
                  ngt2 => 1,
                  nhns => 1,
                  nico => 1,
                  nmer => 1,
                  nmg0 => 1,
                  nmg1 => 1,
                  nmh0 => 1,
                  nmh1 => 1,
                  nmoo => 1,
                  nmr0 => 1,
                  nmr2 => 1,
                  nmr3 => 1,
                  nmr4 => 1,
                  nmr5 => 1,
                  nmr6 => 1,
                  nmr7 => 1,
                  nmr8 => 1,
                  nmr9 => 1,
                  nmra => 1,
                  nmrb => 1,
                  nmrc => 1,
                  nmrd => 1,
                  nmre => 1,
                  nmrf => 1,
                  nmrk => 1,
                  nnzg => 1,
                  nshp => 1,
                  ntav => 1,
                  nten => 1,
                  nth0 => 1,
                  nth1 => 1,
                  ntn2 => 1,
                  ntnt => 1,
                  ntt2 => 1,
                  nwgt => 1,
                  nzin => 1,
                },
                units => {
                  nbsp => 1,
                  ncg1 => 1,
                  ncg2 => 1,
                  ncg3 => 1,
                  ncgb => 1,
                  ndr1 => 1,
                  ndr2 => 1,
                  ndr3 => 1,
                  ngz4 => 1,
                  ngza => 1,
                  ngzc => 1,
                  ngzd => 1,
                  nlv1 => 1,
                  nlv2 => 1,
                  nlv3 => 1,
                  nqb1 => 1,
                  nqb2 => 1,
                  nqb3 => 1,
                  nqb4 => 1,
                  ntor => 1,
                  nwe1 => 1,
                  nwe2 => 1,
                  nwe3 => 1,
                  zcso => 1,
                  zhyd => 1,
                  zjug => 1,
                  zmar => 1,
                  zshv => 1,
                  zsmc => 1,
                  zzrg => 1,
                },
              },
  undead   => {
                buildings => {
                               nbsm => 1,
                               ndmg => 1,
                               nfrm => 1,
                               ngni => 1,
                               nshr => 1,
                               uaod => 1,
                               ubon => 1,
                               ugol => 1,
                               ugrv => 1,
                               unp1 => 1,
                               unp2 => 1,
                               unpl => 1,
                               usap => 1,
                               usep => 1,
                               ushp => 1,
                               uslh => 1,
                               utod => 1,
                               utom => 1,
                               uzg1 => 1,
                               uzg2 => 1,
                               uzig => 1,
                             },
                heroes    => {
                               Nkjx => 1,
                               Nklj => 1,
                               Nmag => 1,
                               Nman => 1,
                               Npld => 1,
                               Uanb => 1,
                               Ubal => 1,
                               Uclc => 1,
                               Ucrl => 1,
                               Udea => 1,
                               Udre => 1,
                               Udth => 1,
                               Uear => 1,
                               Uktl => 1,
                               Ulic => 1,
                               Umal => 1,
                               Usyl => 1,
                               Utic => 1,
                               Uvar => 1,
                               Uvng => 1,
                               Uwar => 1,
                             },
                units     => {
                               nzlc => 1,
                               nzom => 1,
                               uabc => 1,
                               uabo => 1,
                               uaco => 1,
                               uarb => 1,
                               uban => 1,
                               ubdd => 1,
                               ubdr => 1,
                               ubot => 1,
                               ubsp => 1,
                               ucrm => 1,
                               ucry => 1,
                               ucs1 => 1,
                               ucs2 => 1,
                               ucs3 => 1,
                               ucsB => 1,
                               ucsC => 1,
                               udes => 1,
                               ufro => 1,
                               ugar => 1,
                               ugho => 1,
                               ugrm => 1,
                               uktg => 1,
                               uktn => 1,
                               uloc => 1,
                               umtw => 1,
                               unec => 1,
                               uobs => 1,
                               uplg => 1,
                               ushd => 1,
                               uske => 1,
                               uskm => 1,
                               uswb => 1,
                               uubs => 1,
                             },
              },
}

}

# say _item_id_is_upgrade('Rhss');
# say _item_id_is_upgrade('hfoo');
sub _item_id_is_upgrade { my ($item_id) = @_;
    _item_id_is_upgrade_from_race($item_id, 'human')
 || _item_id_is_upgrade_from_race($item_id, 'orc')
 || _item_id_is_upgrade_from_race($item_id, 'orc')
 || _item_id_is_upgrade_from_race($item_id, 'undead')
 || _item_id_is_upgrade_from_race($item_id, 'nightelf')
 # || _item_id_is_upgrade_from_race($item_id, 'naga')
 # || _item_id_is_upgrade_from_race($item_id, 'demon')
}

# say _item_id_upgrade_get_race('Rhss');
sub _item_id_upgrade_get_race { my ($item_id) = @_;
    return 'human' if _item_id_is_upgrade_from_race($item_id, 'human');
    return 'orc' if _item_id_is_upgrade_from_race($item_id, 'orc');
    return 'undead' if _item_id_is_upgrade_from_race($item_id, 'undead');
    return 'nightelf' if _item_id_is_upgrade_from_race($item_id, 'nightelf');
    # return 'naga' if _item_id_is_upgrade_from_race($item_id, 'naga');
    # return 'unknown';
}

sub _item_id_is_upgrade_from_race { my ($item_id, $race) = @_;
    my $upgrades = _item_id_upgrades();
    defined $upgrades->{$race}{$item_id};
}

sub _item_id_upgrades {
    state $upgrades =
{
  demon    => { Roch => 1 },
  human    => {
                Rhac => 1,
                Rhan => 1,
                Rhar => 1,
                Rhcd => 1,
                Rhde => 1,
                Rhfc => 1,
                Rhfl => 1,
                Rhfs => 1,
                Rhgb => 1,
                Rhhb => 1,
                Rhla => 1,
                Rhlh => 1,
                Rhme => 1,
                Rhpm => 1,
                Rhpt => 1,
                Rhra => 1,
                Rhri => 1,
                Rhrt => 1,
                Rhse => 1,
                Rhss => 1,
                Rhst => 1,
              },
  naga     => { Rnam => 1, Rnat => 1, Rnen => 1, Rnsb => 1, Rnsi => 1, Rnsw => 1 },
  nightelf => {
                Recb => 1,
                Redc => 1,
                Redt => 1,
                Reeb => 1,
                Reec => 1,
                Rehs => 1,
                Reht => 1,
                Reib => 1,
                Rema => 1,
                Remg => 1,
                Remk => 1,
                Renb => 1,
                Repb => 1,
                Repm => 1,
                Rerh => 1,
                Rers => 1,
                Resc => 1,
                Resi => 1,
                Resm => 1,
                Resw => 1,
                Reuv => 1,
                Rews => 1,
              },
  orc      => {
                Roar => 1,
                Robf => 1,
                Robk => 1,
                Robs => 1,
                Roen => 1,
                Rolf => 1,
                Rome => 1,
                Ropg => 1,
                Ropm => 1,
                Rora => 1,
                Rorb => 1,
                Rosp => 1,
                Rost => 1,
                Rotr => 1,
                Rovs => 1,
                Rowd => 1,
                Rows => 1,
                Rowt => 1,
                Rwdm => 1,
              },
  undead   => {
                Ruac => 1,
                Ruar => 1,
                Ruba => 1,
                Rubu => 1,
                Rucr => 1,
                Ruex => 1,
                Rufb => 1,
                Rugf => 1,
                Rume => 1,
                Rune => 1,
                Rupc => 1,
                Rupm => 1,
                Rura => 1,
                Rusf => 1,
                Rusl => 1,
                Rusm => 1,
                Rusp => 1,
                Ruwb => 1,
              },
  unknown  => { Rgfo => 1, Rguv => 1 },
};

}

# say _item_id_is_hero_ability('AOfs');
# say _item_id_is_hero_ability('hfoo');
sub _item_id_is_hero_ability { my ($item_id) = @_;
    my $abilities_for_hero = _item_id_hero_abilities();
    for my $hero_id (keys %$abilities_for_hero) {
        return 1 if defined $abilities_for_hero->{$hero_id}{$item_id};
    }
    return 0;
}

# say _item_id_unit_ability_get_hero('AOfs');
sub _item_id_unit_ability_get_hero { my ($ability_id) = @_;
    my $abilities_for_hero = _item_id_hero_abilities();
    for my $hero_id (keys %$abilities_for_hero) {
        return $hero_id if defined $abilities_for_hero->{$hero_id}{$ability_id};
    }
    return 0;
}

sub _item_id_hero_abilities {
    state $hero_abilities =
{
  # Ecen => { AEah => 1, AEer => 1, AEfn => 1, AEtq => 1 },
  Edem => { AEev => 1, AEim => 1, AEmb => 1, AEme => 1 },
  # Edmm => { AEev => 1, AEim => 1, AEmb => 1, AEme => 1 },
  # Eevi => { AEev => 1, AEim => 1, AEmb => 1, AEvi => 1 },
  # Eevm => { AEev => 1, AEim => 1, AEmb => 1, AEvi => 1 },
  # Efur => { AEah => 1, AEer => 1, AEfn => 1, AEtq => 1 },
  # Eidm => { AEev => 1, AEim => 1, AEmb => 1 },
  # Eill => { AEev => 1, AEIl => 1, AEim => 1, AEmb => 1 },
  # Eilm => { AEev => 1, AEIl => 1, AEim => 1, AEmb => 1 },
  Ekee => { AEah => 1, AEer => 1, AEfn => 1, AEtq => 1 },
  # Ekgg => { AEah => 1, AEer => 1, AEfn => 1, AEtq => 1 },
  # Emfr => { AEah => 1, AEer => 1, AEfn => 1, AEtq => 1 },
  # Emns => { AEah => 1, AEer => 1, AEfn => 1, AEtq => 1 },
  Emoo => { AEar => 1, AEsf => 1, AEst => 1, AHfa => 1 },
  # Etyr => { AEar => 1, AEsf => 1, AEst => 1, AHfa => 1 },
  Ewar => { AEbl => 1, AEfk => 1, AEsh => 1, AEsv => 1 },
  # Ewrd => { AEbl => 1, AEfk => 1, AEsh => 1, AEsv => 1 },
  Hamg => { AHab => 1, AHbz => 1, AHmt => 1, AHwe => 1 },
  # Hant => { AHab => 1, AHbz => 1, AHmt => 1, AHwe => 1 },
  # Harf => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Hart => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  Hblm => { AHbn => 1, AHdr => 1, AHfs => 1, AHpx => 1 },
  # Hdgo => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Hgam => { AHab => 1, AHbz => 1, AHmt => 1, AHwe => 1 },
  # Hhkl => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Hjai => { AHab => 1, AHbz => 1, AHmt => 1, AHwe => 1 },
  # Hkal => { AHbn => 1, AHdr => 1, AHfs => 1, AHpx => 1 },
  # Hlgr => { AHad => 1, AHhb => 1, ANav => 1, ANsh => 1 },
  # Hmbr => { AHav => 1, AHbh => 1, AHtb => 1, AHtc => 1 },
  # Hmgd => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  Hmkg => { AHav => 1, AHbh => 1, AHtb => 1, AHtc => 1 },
  Hpal => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Hpb1 => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Hpb2 => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Huth => { AHad => 1, AHds => 1, AHhb => 1, AHre => 1 },
  # Hvsh => { ANfa => 1, ANfl => 1, ANms => 1, ANto => 1 },
  # Hvwd => { AEar => 1, AEsf => 1, AEst => 1, AHca => 1 },
  # Naka => { ACs7 => 1, AEsh => 1, ANr2 => 1, AOcl => 1 },
  # Nal2 => { ANab => 1, ANcr => 1, ANhs => 1, ANtm => 1 },
  # Nal3 => { ANab => 1, ANcr => 1, ANhs => 1, ANtm => 1 },
  Nalc => { ANab => 1, ANcr => 1, ANhs => 1, ANtm => 1 },
  # Nalm => { ANab => 1, ANcr => 1, ANhs => 1, ANtm => 1 },
  # Nbbc => { AOcr => 1, AOmi => 1, AOwk => 1, AOww => 1 },
  Nbrn => { ANba => 1, ANch => 1, ANdr => 1, ANsi => 1 },
  Nbst => { ANsg => 1, ANsq => 1, ANst => 1, ANsw => 1 },
  Nfir => { ANia => 1, ANlm => 1, ANso => 1, ANvc => 1 },
  # Nmag => { ANca => 1, ANdo => 1, ANht => 1, ANrf => 1 },
  # Nman => { AHtc => 1, ANrn => 1, AOeq => 1, AOsh => 1 },
  Nngs => { ANfa => 1, ANfl => 1, ANms => 1, ANto => 1 },
  Npbm => { ANbf => 1, ANdb => 1, ANdh => 1, ANef => 1 },
  # Npld => { AHtc => 1, ANrn => 1, AOeq => 1, AOsh => 1 },
  Nplh => { ANca => 1, ANdo => 1, ANht => 1, ANrf => 1 },
  # Nrob => { ANcs => 1, ANeg => 1, ANrg => 1, ANsy => 1 },
  # Nsjs => { Aamk => 1, Acdb => 1, Acdh => 1, Acef => 1, ANcf => 1 },
  Ntin => { ANcs => 1, ANeg => 1, ANrg => 1, ANsy => 1 },
  Obla => { AOcr => 1, AOmi => 1, AOwk => 1, AOww => 1 },
  # Ocb2 => { Aamk => 1, AOr2 => 1, AOr3 => 1, AOs2 => 1, AOw2 => 1 },
  # Ocbh => { AOae => 1, AOre => 1, AOsh => 1, AOws => 1 },
  # Odrt => { AOcl => 1, AOeq => 1, AOfs => 1, AOsf => 1 },
  Ofar => { AOcl => 1, AOeq => 1, AOfs => 1, AOsf => 1 },
  # Ogrh => { AOcr => 1, AOmi => 1, AOwk => 1, AOww => 1 },
  # Opgh => { AOcr => 1, AOmi => 1, AOwk => 1, AOww => 1 },
  # Orex => { Aamk => 1, ANsb => 1, Arsg => 1, Arsp => 1, Arsq => 1 },
  # Orkn => { Aamk => 1, ANhw => 1, ANhx => 1, AOls => 1, Arsw => 1 },
  # Osam => { AOcr => 1, AOmi => 1, AOwk => 1, AOww => 1 },
  Oshd => { AOhw => 1, AOhx => 1, AOsw => 1, AOvd => 1 },
  # Otcc => { AOae => 1, AOre => 1, AOsh => 1, AOws => 1 },
  Otch => { AOae => 1, AOre => 1, AOsh => 1, AOws => 1 },
  # Othr => { AOcl => 1, AOeq => 1, AOfs => 1, AOsf => 1 },
  # Uanb => { AUcb => 1, AUim => 1, AUls => 1, AUts => 1 },
  # Ubal => { ACf3 => 1, ANr3 => 1, AOeq => 1, AUav => 1, AUsl => 1 },
  # Uclc => { AUdd => 1, AUdr => 1, AUfn => 1, AUfu => 1 },
  Ucrl => { AUcb => 1, AUim => 1, AUls => 1, AUts => 1 },
  Udea => { AUan => 1, AUau => 1, AUdc => 1, AUdp => 1 },
  Udre => { AUav => 1, AUcs => 1, AUin => 1, AUsl => 1 },
  # Udth => { AEsh => 1, AUcs => 1, AUdd => 1, AUsl => 1 },
  # Uear => { AUan => 1, AUau => 1, AUdc => 1, AUdp => 1 },
  # Uktl => { AUdd => 1, AUdr => 1, AUfn => 1, AUfu => 1 },
  Ulic => { AUdd => 1, AUdr => 1, AUfn => 1, AUfu => 1 },
  # Umal => { ANdc => 1, ANsl => 1, AUcs => 1, AUsl => 1 },
  # Usyl => { ANba => 1, ANch => 1, ANdr => 1, ANsi => 1 },
  # Utic => { ANfd => 1, ANrc => 1, AUcs => 1, AUsl => 1 },
  # Uvar => { ANdo => 1, ANrf => 1, AUav => 1, AUsl => 1 },
  # Uvng => { AUav => 1, AUcs => 1, AUin => 1, AUsl => 1 },
  # Uwar => { AHbh => 1, ANdp => 1, ANfd => 1, ANrc => 1 },
}

}

sub _zlib_decompress { my ($compressed_data) = @_;
    # https://metacpan.org/pod/Compress::Zlib#Inflate-Interface
    # "To uncompress an RFC 1951 data stream, set WindowBits to -MAX_WBITS"
    my $zlib = inflateInit(-WindowBits => -MAX_WBITS());

    # $compressed_data = substr $compressed_data, 2, -4;
    $compressed_data = substr $compressed_data, 2;

    # Without this line the inflation doesn't work.
    # The comment from w3g-julas.php by Juliusz 'Julas' Gonera.
    # // the first bit must be always set, but already set in replays with modified chatlog (why?)
    # $temp{0} = chr(ord($temp{0}) | 1);
    substr($compressed_data, 0, 1) = chr(ord(substr $compressed_data, 0, 1) | 1);

    my ($decompressed_data, $status) = $zlib->inflate($compressed_data);

    $decompressed_data;
}

sub _players_calculate_game_result { my ($players, $leave_game_blocks) = @_;
    my $saver_id = 1;
    if (@$leave_game_blocks) {
        $saver_id = $leave_game_blocks->[-1]{'player_id'};
    }
    my $saver = $players->{$saver_id};
    # use DDP; say p $leave_game_blocks;

    for my $i (0 .. $#{$leave_game_blocks}) {
        my $leave_game_block = $leave_game_blocks->[$i];
        my $reason           = $leave_game_block->{'reason'};
        my $result           = $leave_game_block->{'result'};
        my $cp               = $players->{$leave_game_block->{'player_id'}};

        my $leave_game_block_is_last = $i == $#{$leave_game_blocks};

        if ($reason eq 'connection_closed_by_remote_game') {
            if ($result == 0x07 || $result == 0x08) {
                $cp->{'game_result'} = 'defeat';
            } elsif ($result == 0x09) {
                $cp->{'game_result'} = 'victory';
            } elsif ($result == 0x0A) {
                $cp->{'game_result'} = 'tie';
            } else {
                $cp->{'game_result'} = 'unknown1';
            }
        } elsif ($reason eq 'connection_closed_by_local_game' && !$leave_game_block_is_last) {
            if ($result == 0x08) {
                $saver->{'game_result'} = 'defeat';
            } elsif ($result == 0x09) {
                $saver->{'game_result'} = 'victory';
            } elsif ($result == 0xA) {
                $saver->{'game_result'} = 'tie';
            } else {
                $cp->{'game_result'} = 'unknown2';
            }
        } elsif ($reason eq 'connection_closed_by_local_game' && $leave_game_block_is_last) {
            my $INC = $leave_game_block->{'unknown'};
            if ($result == 0x01) {
                $saver->{'game_result'} = 'disconnected';
            } elsif ($result == 0x07) {
                if ($INC) {
                    $saver->{'game_result'} = 'victory';
                } else {
                    $saver->{'game_result'} = 'defeat';
                }
            } elsif ($result == 0x08) {
                $saver->{'game_result'} = 'defeat';
            } elsif ($result == 0x09) {
                $saver->{'game_result'} =  'victory';
            } elsif ($result == 0x0B) { # [?]
                if ($INC) {
                    $saver->{'game_result'} = 'victory';
                } else {
                    $saver->{'game_result'} = 'defeat';
                }
            } else {
                $cp->{'game_result'} = 'unknown3';
            }
        } else {
            $cp->{'game_result'} = 'unknown4';
        }
    }

    # maybe TODO:
    # for team games if any player in a team is victorious/defeated/tied then
    # the whole team is victorious/defeated/tied respectivly
}

# Returns a "nicely" formated hash with keys and values which are actually usefull.
sub _replay { my ($header, $gmp_info, $player_actions, $chat, $game_duration) = @_;
    my $replay = {};

    my $map_settings = $gmp_info->{'map_settings'};

    $replay->{'game'}    = {};
    my $game             = $replay->{'game'};
    $game->{'version'}   = $header->{'game_version_flag'};
    $game->{'name'}      = $gmp_info->{'game_name'};
    $game->{'creator'}   = $map_settings->{'game_creator_name'};
    $game->{'is_public'} = $gmp_info->{'game_is_public'};
    $game->{'type'}      = $gmp_info->{'game_type'};
    $game->{'speed'}     = $map_settings->{'game_speed'};
    $game->{'duration'}  = $game_duration;

    my $map_name                = $map_settings->{'map_name'};
    my ($filename, $dirname)    = File::Basename::fileparse($map_name);
    $replay->{'map'}            = {};
    my $map                     = $replay->{'map'};
    $map->{'dirname'}           = $dirname;
    $map->{'filename'}          = $filename;
    $map->{'fullpath'}          = $map_name;
    $map->{'advanced_settings'} = {};

    my $advanced_settings                            = $map->{'advanced_settings'};
    $advanced_settings->{'lock_teams'}               = $map_settings->{'lock_teams'};
    $advanced_settings->{'observer'}                 = $map_settings->{'advanced_settings'}{'observer'};
    $advanced_settings->{'teams_together'}           = $map_settings->{'advanced_settings'}{'teams_together'};
    $advanced_settings->{'visibility'}               = $map_settings->{'advanced_settings'}{'visibility'};
    $advanced_settings->{'full_shared_unit_control'} = $map_settings->{'more_advanced_settings'}{'full_shared_unit_control'};
    $advanced_settings->{'random_hero'}              = $map_settings->{'more_advanced_settings'}{'random_hero'};
    $advanced_settings->{'random_races'}             = $map_settings->{'more_advanced_settings'}{'random_races'};

    my @slots = @{ $gmp_info->{'GameStartRecord'}{'SlotRecord'} };
    my @slots_copy = @slots;
    @slots    = grep { $_->{'slot_status'} ne 'empty' } @slots;
    my @players_or_observers = (
        $gmp_info->{'game_creator'}{'PlayerRecord'},
        grep { defined } map { $_->{'player'}{'PlayerRecord'}; } @{ $gmp_info->{'players'} },
    );

    # use DDP; say p @slots_copy;
    # use DDP; say p @slots;
    # use DDP; say p @players_or_observers;

    my @player_slots   = grep { $_->{'team_number'} != 12 } @slots;
    # my @observer_slots = grep { $_->{'team_number'} == 12 } @slots;
    my @player_records = grep {
        my $p = $_;
        my $slot = first_value { $p->{'id'} == $_->{'player_id'} } @slots;
        $slot->{'team_number'} != 12;
    } @players_or_observers;
    my @observers = grep {
        my $o = $_;
        my $slot = first_value { $o->{'id'} == $_->{'player_id'} } @slots;
        $slot->{'team_number'} == 12;
    } @players_or_observers;

    # use DDP; say p @player_slots;
    # use DDP; say p @player_records;
    # use DDP; say p @observer_slots;
    # use DDP; say p @observers;

    @player_slots = sort_by { $_->{'player_id'} } @player_slots;
    @player_records = sort_by { $_->{'id'} } @player_records;
    # use DDP; say p @player_slots;
    # use DDP; say p @player_records;

    my @players;
    for my $i (0 .. $#player_slots) {
        my $player      = $player_records[$i];
        my $player_slot = $player_slots[$i];

        if (!$player_slot->{'is_ai'}) {
            $players[$i] = {
                id         => $player->{'id'},
                name       => $player->{'name'} || "Player $player->{'id'}",
                is_ai      => 0,
                team       => $player_slot->{'team_number'},
                main_race  => $player_slot->{'race'},
                color      => $player_slot->{'color_number'},
                handicap   => $player_slot->{'handicap'},
                slot_index => 1 + first_index { $_->{'player_id'} == $player->{'id'} } @slots_copy,
            };
        } else {
            my $computer_name = 'Computer (' . ucfirst($player_slot->{'ai_strength'}) . ')' ;
            $players[$i] = {
                name       => $computer_name,
                is_ai      => 1,
                team       => $player_slot->{'team_number'},
                main_race  => $player_slot->{'race'},
                color      => $player_slot->{'color_number'},
                handicap   => $player_slot->{'handicap'},
                slot_index => 1 + first_index { $_->{'player_id'} == $player->{'id'} } @slots_copy,
            };
        }
    }

    @observers = map { my $obs = $_; +{
        name       => $obs->{'name'},
        id         => $obs->{'id'},
        slot_index => 1 + first_index { $_->{'player_id'} == $obs->{'id'} } @slots_copy
    } } @observers;

    # use DDP; say p @players;
    # use DDP; say p @observers;

    my $required_player_attrs = { build_order => {},  actions_count => 0 };

    for my $player (@players) {
        next if $player->{'is_ai'};
        delete $player_actions->{ $player->{'id'} }{'last'};
        delete $player_actions->{ $player->{'id'} }{'object_ids'};
        delete $player_actions->{ $player->{'id'} }{'selection'};
        @{ $player_actions->{ $player->{'id'} } }{keys %$player} = values %$player;

        while (my ($attr_name, $attr_default_value) = each %$required_player_attrs) {
            $player_actions->{$player->{'id'}}{$attr_name} //= $attr_default_value;
        }
    }

    # Ged rid of "bogus players" (actually observers that used the minimap signalig or something)
    # but got into the $players hash.
    $player_actions = {
        map {
            defined $player_actions->{$_}{'name'} ? ($_, $player_actions->{$_}) : ()
        } keys %$player_actions
    };
    $replay->{'players'}   = $player_actions;
    $replay->{'observers'} = [ @observers ];

    $replay->{'chat'} = $chat;

    $replay;
}

sub _debug_action_blocks { my ($blocks) = @_;
    state $block_time_slot_id = _block_name_to_id('time_slot');
    state $action_ids         = [0x10, 0x11, 0x12, 0x13, 0x14, 0x17, 0x18, 0x19];

    for my $block (@$blocks) {
        next if $block->{'block_id'} != $block_time_slot_id;
        next if !defined $block->{'block'}{'command_data'};

        $block->{'block'}{'parsed_command_data'} = _command_data_player()->parse($block->{'block'}{'command_data'});
        my $command_data_player = $block->{'block'}{'parsed_command_data'}{'command_data_player'};
        for my $command_data_player (@$command_data_player) {
            $command_data_player->{'parsed_player_actions'}
          = _command_data_player_actions()->parse($command_data_player->{'player_actions'})
            ;

            my $parsed_player_actions = $command_data_player->{'parsed_player_actions'};
            for my $action_block (@{ $parsed_player_actions->{'action_block'} }) {
                $action_block->{'action_name'} = _action_id_to_name($action_block->{'action_id'});

                my $action_id = $action_block->{'action_id'};
                next if none { $action_id == $_ } @$action_ids;
                _debug_action_blocks_translate_item_ids_action_0x10($action_block) if $action_id == 0x10;
                _debug_action_blocks_translate_item_ids_action_0x11($action_block) if $action_id == 0x11;
                _debug_action_blocks_translate_item_ids_action_0x12($action_block) if $action_id == 0x12;
                _debug_action_blocks_translate_item_ids_action_0x13($action_block) if $action_id == 0x13;
                _debug_action_blocks_translate_item_ids_action_0x14($action_block) if $action_id == 0x14;
                _debug_action_blocks_translate_item_ids_action_0x19($action_block) if $action_id == 0x19;
                # use DDP; say p $action_block and exit 1 if $action_id == 0x17;
            }

            # filter selection, grouping, enter_choose actions (a lot of them but they are not intresting)
            $parsed_player_actions->{'action_block'} = [ grep {
                # $_->{'action_name'} !~ /select|group|enter_choose/
                # $_->{'action_name'} !~ /select|enter_choose/
                # $_->{'action_name'} !~ /enter_choose/
                # 0
                1
            } @{ $parsed_player_actions->{'action_block'} } ];

            # filter action blocks about item ids of orders (smart, attack, etc.)
            $parsed_player_actions->{'action_block'} = [ grep {
                my $action_block = $_;

                my $action_unit = $action_block->{'action'}{'action_unit_loc_target'}{'action_unit'};
                $action_unit    = $action_block->{'action'}{'action_unit'} if !defined $action_unit;

                my $item_id = $action_unit->{'item_id'};
                defined $item_id ? $item_id !~ /smart|setrally|attack|move/ : 1;

            } @{ $parsed_player_actions->{'action_block'} } ];
        }

        $command_data_player = [ grep {
            @{ $_->{'parsed_player_actions'}{'action_block'} } > 0
            # 1

        # filter by player_id
         # && $_->{'player_id'} == 6;
        } @$command_data_player ];

        $block->{'block'}{'parsed_command_data'}{'command_data_player'} = $command_data_player;
    }

    $blocks = [ grep {
        $_->{'block_id'} != $block_time_slot_id ? 1
      : defined $_->{'block'}{'parsed_command_data'}
     && @{ $_->{'block'}{'parsed_command_data'}{'command_data_player'} } > 0
    } @$blocks ];

    use Encode; use DDP; say encode 'UTF-8', p $blocks;
}

sub _debug_action_blocks_translate_item_ids_action_0x10 { my ($action_block) = @_;
    my $action_unit = $action_block->{'action'}{'action_unit'};
    my $item_id = $action_unit->{'item_id'};
    if ($item_id >= STRING_ENCODED_ITEM_ID_MIN_DECIMAL_VALUE) {
        $action_unit->{'item_id'} = _decimal_to_string_encoded_item_id($item_id);
    } else {
        $action_unit->{'item_id'} = _numerical_item_id_to_name($item_id);
    }
}

sub _debug_action_blocks_translate_item_ids_action_0x11 { my ($action_block) = @_;
    _debug_action_blocks_translate_item_ids_action_0x10($action_block);
}

sub _debug_action_blocks_translate_item_ids_action_0x12 { my ($action_block) = @_;
    my $action_unit = $action_block->{'action'}{'action_unit_loc_target'}{'action_unit'};
    my $item_id = $action_unit->{'item_id'};
    if ($item_id >= STRING_ENCODED_ITEM_ID_MIN_DECIMAL_VALUE) {
        $action_unit->{'item_id'} = _decimal_to_string_encoded_item_id($item_id);
    } else {
        $action_unit->{'item_id'} = _numerical_item_id_to_name($item_id);
    }
}

sub _debug_action_blocks_translate_item_ids_action_0x13 { my ($action_block) = @_;
    _debug_action_blocks_translate_item_ids_action_0x12($action_block);
}

sub _debug_action_blocks_translate_item_ids_action_0x14 { my ($action_block) = @_;
    my $action = $action_block->{'action'};
    my $item_id_a = $action->{'item_id_a'};
    if ($item_id_a >= STRING_ENCODED_ITEM_ID_MIN_DECIMAL_VALUE) {
        $action->{'item_id_a'} = _decimal_to_string_encoded_item_id($item_id_a);
    } else {
        $action->{'item_id_a'} = _numerical_item_id_to_name($item_id_a);
    }
}

sub _debug_action_blocks_translate_item_ids_action_0x19 { my ($action_block) = @_;
    my $select_subgroup = $action_block->{'action'}{'action_select_subgroup'};
    $select_subgroup->{'item_id'} = _decimal_to_string_encoded_item_id($select_subgroup->{'item_id'});
}

1;