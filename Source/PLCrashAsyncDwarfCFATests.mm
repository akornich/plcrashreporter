/*
 * Author: Landon Fuller <landonf@plausible.coop>
 *
 * Copyright (c) 2012-2013 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "PLCrashTestCase.h"

#include "PLCrashAsyncDwarfCFA.hpp"
#include "PLCrashAsyncDwarfExpression.h"

#define DW_CFA_BAD_OPCODE DW_CFA_hi_user

using namespace plcrash::async;

@interface PLCrashAsyncDwarfCFATests : PLCrashTestCase {
    dwarf_cfa_state _stack;
    plcrash_async_dwarf_gnueh_ptr_state_t _ptr_state;
    plcrash_async_dwarf_cie_info_t _cie;
}
@end

/**
 * Test DWARF CFA interpretation.
 */
@implementation PLCrashAsyncDwarfCFATests

- (void) setUp {
    /* Initialize required configuration for pointer dereferencing */
    plcrash_async_dwarf_gnueh_ptr_state_init(&_ptr_state, 4);

    _cie.segment_size = 0x0; // we don't use segments
    _cie.has_eh_augmentation = true;
    _cie.eh_augmentation.has_pointer_encoding = true;
    _cie.eh_augmentation.pointer_encoding = DW_EH_PE_absptr; // direct pointers
    
    _cie.code_alignment_factor = 1;
    _cie.data_alignment_factor = 1;
    
    _cie.address_size = _ptr_state.address_size;
}

- (void) tearDown {
    plcrash_async_dwarf_gnueh_ptr_state_free(&_ptr_state);
}

/* Perform evaluation of the given opcodes, expecting a result of type @a type,
 * with an expected value of @a expected. The data is interpreted as big endian. */
#define PERFORM_EVAL_TEST(opcodes, pc_offset, expected) do { \
    plcrash_async_mobject_t mobj; \
    plcrash_error_t err; \
    STAssertEquals(PLCRASH_ESUCCESS, plcrash_async_mobject_init(&mobj, mach_task_self(), (pl_vm_address_t) &opcodes, sizeof(opcodes), true), @"Failed to initialize mobj"); \
    \
        err = plcrash_async_dwarf_cfa_eval_program(&mobj, (pl_vm_address_t)pc_offset, &_cie, &_ptr_state, plcrash_async_byteorder_big_endian(), (pl_vm_address_t) &opcodes, 0, sizeof(opcodes), &_stack); \
        STAssertEquals(err, expected, @"Evaluation failed"); \
    \
    plcrash_async_mobject_free(&mobj); \
} while(0)

/* Validate the rule type and value of a register state in _stack */
#define TEST_REGISTER_RESULT(_regnum, _type, _expect_val) do { \
    plcrash_dwarf_cfa_reg_rule_t rule; \
    int64_t value; \
    STAssertTrue(_stack.get_register_rule(_regnum, &rule, &value), @"Failed to fetch rule"); \
    STAssertEquals(_type, rule, @"Incorrect rule returned"); \
    STAssertEquals(_expect_val, value, @"Incorrect value returned"); \
} while (0)

/** Test evaluation of DW_CFA_set_loc */
- (void) testSetLoc {
    /* This should terminate once our PC offset is hit below; otherwise, it will execute a
     * bad CFA instruction and return falure */
    uint8_t opcodes[] = { DW_CFA_set_loc, 0x1, 0x2, 0x3, 0x4, DW_CFA_BAD_OPCODE};
    PERFORM_EVAL_TEST(opcodes, 0x1020304, PLCRASH_ESUCCESS);
    
    /* Test evaluation without GNU EH agumentation data (eg, using direct word sized pointers) */
    _cie.has_eh_augmentation = false;
    PERFORM_EVAL_TEST(opcodes, 0x1020304, PLCRASH_ESUCCESS);
}

/** Test evaluation of DW_CFA_advance_loc */
- (void) testAdvanceLoc {
    _cie.code_alignment_factor = 2;
    
    /* Evaluation should terminate prior to the bad opcode */
    uint8_t opcodes[] = { DW_CFA_advance_loc|0x1, DW_CFA_BAD_OPCODE};
    PERFORM_EVAL_TEST(opcodes, 0x2, PLCRASH_ESUCCESS);
}


/** Test evaluation of DW_CFA_advance_loc1 */
- (void) testAdvanceLoc1 {
    _cie.code_alignment_factor = 2;
    
    /* Evaluation should terminate prior to the bad opcode */
    uint8_t opcodes[] = { DW_CFA_advance_loc1, 0x1, DW_CFA_BAD_OPCODE};
    PERFORM_EVAL_TEST(opcodes, 0x2, PLCRASH_ESUCCESS);
}

/** Test evaluation of DW_CFA_advance_loc2 */
- (void) testAdvanceLoc2 {
    _cie.code_alignment_factor = 2;
    
    /* Evaluation should terminate prior to the bad opcode */
    uint8_t opcodes[] = { DW_CFA_advance_loc2, 0x0, 0x1, DW_CFA_BAD_OPCODE};
    PERFORM_EVAL_TEST(opcodes, 0x2, PLCRASH_ESUCCESS);
}

/** Test evaluation of DW_CFA_advance_loc2 */
- (void) testAdvanceLoc4 {
    _cie.code_alignment_factor = 2;
    
    /* Evaluation should terminate prior to the bad opcode */
    uint8_t opcodes[] = { DW_CFA_advance_loc4, 0x0, 0x0, 0x0, 0x1, DW_CFA_BAD_OPCODE};
    PERFORM_EVAL_TEST(opcodes, 0x2, PLCRASH_ESUCCESS);
}

/** Test evaluation of DW_CFA_def_cfa */
- (void) testDefineCFA {
    uint8_t opcodes[] = { DW_CFA_def_cfa, 0x1, 0x2};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);

    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_REGISTER, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((uint32_t)1, _stack.get_cfa_rule().reg.regnum, @"Unexpected CFA register");
    STAssertEquals((int64_t)2, _stack.get_cfa_rule().reg.offset, @"Unexpected CFA offset");
}

/** Test evaluation of DW_CFA_def_cfa_sf */
- (void) testDefineCFASF {
    /* An alignment factor to be applied to the second operand. */
    _cie.data_alignment_factor = 2;

    uint8_t opcodes[] = { DW_CFA_def_cfa_sf, 0x1, 0x7e /* -2 */};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);

    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_REGISTER_SIGNED, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((uint32_t)1, _stack.get_cfa_rule().reg.regnum, @"Unexpected CFA register");
    STAssertEquals((int64_t)-4, (int64_t)_stack.get_cfa_rule().reg.offset, @"Unexpected CFA offset");
}

/** Test evaluation of DW_CFA_def_cfa_register */
- (void) testDefineCFARegister {
    uint8_t opcodes[] = { DW_CFA_def_cfa, 0x1, 0x2, DW_CFA_def_cfa_register, 10 };
    
    /* Verify modification of unsigned state */
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);

    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_REGISTER, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((uint32_t)10, _stack.get_cfa_rule().reg.regnum, @"Unexpected CFA register");
    STAssertEquals((int64_t)2, _stack.get_cfa_rule().reg.offset, @"Unexpected CFA offset");
    
    /* Verify modification of signed state */
    opcodes[0] = DW_CFA_def_cfa_sf;
    opcodes[2] = 0x7e; /* -2 */
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    
    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_REGISTER_SIGNED, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((uint32_t)10, _stack.get_cfa_rule().reg.regnum, @"Unexpected CFA register");
    STAssertEquals((int64_t)-2, (int64_t)_stack.get_cfa_rule().reg.offset, @"Unexpected CFA offset");
    
    /* Verify behavior when a non-register CFA rule is present */
    _stack.set_cfa_expression(0);
    opcodes[0] = DW_CFA_nop;
    opcodes[1] = DW_CFA_nop;
    opcodes[2] = DW_CFA_nop;
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_EINVAL);
}

/** Test evaluation of DW_CFA_def_cfa_offset */
- (void) testDefineCFAOffset {
    uint8_t opcodes[] = { DW_CFA_def_cfa, 0x1, 0x2, DW_CFA_def_cfa_offset, 10 };    
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    
    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_REGISTER, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((uint32_t)1, _stack.get_cfa_rule().reg.regnum, @"Unexpected CFA register");
    STAssertEquals((int64_t)10, _stack.get_cfa_rule().reg.offset, @"Unexpected CFA offset");

    /* Verify behavior when a non-register CFA rule is present */
    _stack.set_cfa_expression(0);
    opcodes[0] = DW_CFA_nop;
    opcodes[1] = DW_CFA_nop;
    opcodes[2] = DW_CFA_nop;
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_EINVAL);
}

/** Test evaluation of DW_CFA_def_cfa_offset_sf */
- (void) testDefineCFAOffsetSF {
    /* An alignment factor to be applied to the signed offset operand. */
    _cie.data_alignment_factor = 2;

    uint8_t opcodes[] = { DW_CFA_def_cfa, 0x1, 0x2, DW_CFA_def_cfa_offset_sf, 0x7e /* -2 */ };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    
    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_REGISTER_SIGNED, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((uint32_t)1, _stack.get_cfa_rule().reg.regnum, @"Unexpected CFA register");
    STAssertEquals((int64_t)-4, (int64_t)_stack.get_cfa_rule().reg.offset, @"Unexpected CFA offset");
    
    /* Verify behavior when a non-register CFA rule is present */
    _stack.set_cfa_expression(0);
    opcodes[0] = DW_CFA_nop;
    opcodes[1] = DW_CFA_nop;
    opcodes[2] = DW_CFA_nop;
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_EINVAL);
}

/** Test evaluation of DW_CFA_def_cfa_expression */
- (void) testDefineCFAExpression {    
    uint8_t opcodes[] = { DW_CFA_def_cfa_expression, 0x1 /* 1 byte long */, DW_OP_nop /* expression opcodes */};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    
    STAssertEquals(DWARF_CFA_STATE_CFA_TYPE_EXPRESSION, _stack.get_cfa_rule().cfa_type, @"Unexpected CFA type");
    STAssertEquals((pl_vm_address_t) &opcodes[1], _stack.get_cfa_rule().expression.address, @"Unexpected expression address");
}

/** Test evaluation of DW_CFA_undefined */
- (void) testUndefined {
    plcrash_dwarf_cfa_reg_rule_t rule;
    int64_t value;

    /* Define the register */
    _stack.set_register(1, PLCRASH_DWARF_CFA_REG_RULE_OFFSET, 10);
    STAssertTrue(_stack.get_register_rule(1, &rule, &value), @"Rule should be marked as defined");

    /* Perform undef */
    uint8_t opcodes[] = { DW_CFA_undefined, 0x1 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    STAssertFalse(_stack.get_register_rule(1, &rule, &value), @"No rule should be defined for undef register");
}

/** Test evaluation of DW_CFA_same_value */
- (void) testSameValue {
    uint8_t opcodes[] = { DW_CFA_same_value, 0x1 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    
    plcrash_dwarf_cfa_reg_rule_t rule;
    int64_t value;
    STAssertTrue(_stack.get_register_rule(1, &rule, &value), @"Failed to fetch rule");
    STAssertEquals(PLCRASH_DWARF_CFA_REG_RULE_SAME_VALUE, rule, @"Incorrect rule returned");
}

/** Test evaluation of DW_CFA_offset */
- (void) testOffset {
    _cie.data_alignment_factor = 2;

    // This opcode encodes the register value in the low 6 bits
    uint8_t opcodes[] = { DW_CFA_offset|0x4, 0x5 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_OFFSET, (int64_t)0xA);
}

/** Test evaluation of DW_CFA_offset_extended */
- (void) testOffsetExtended {
    _cie.data_alignment_factor = 2;

    uint8_t opcodes[] = { DW_CFA_offset_extended, 0x4, 0x5 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_OFFSET, (int64_t)0xA);
}

/** Test evaluation of DW_CFA_offset_extended_sf */
- (void) testOffsetExtendedSF {
    _cie.data_alignment_factor = -1;
    
    uint8_t opcodes[] = { DW_CFA_offset_extended_sf, 0x4, 0x4 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_OFFSET, (int64_t)-4);
}

/** Test evaluation of DW_CFA_val_offset */
- (void) testValOffset {
    _cie.data_alignment_factor = -1;

    uint8_t opcodes[] = { DW_CFA_val_offset, 0x4, 0x4 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_VAL_OFFSET, (int64_t)-4);
}

/** Test evaluation of DW_CFA_val_offset_sf */
- (void) testValOffsetSF {
    _cie.data_alignment_factor = -1;
    
    uint8_t opcodes[] = { DW_CFA_val_offset_sf, 0x4, 0x7e /* -2 */ };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_VAL_OFFSET, (int64_t)2);
}

/** Test evaluation of DW_CFA_register */
- (void) testRegister {
    _cie.data_alignment_factor = -1;
    
    uint8_t opcodes[] = { DW_CFA_register, 0x4, 0x5};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_REGISTER, (int64_t)0x5);
}

/** Test evaluation of DW_CFA_expression */
- (void) testExpression {
    uint8_t opcodes[] = { DW_CFA_expression, 0x4, 0x1 /* 1 byte long */, DW_OP_nop /* expression opcodes */};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, (int64_t)&opcodes[2]);
}

/** Test evaluation of DW_CFA_val_expression */
- (void) testValExpression {
    uint8_t opcodes[] = { DW_CFA_val_expression, 0x4, 0x1 /* 1 byte long */, DW_OP_nop /* expression opcodes */};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_VAL_EXPRESSION, (int64_t)&opcodes[2]);
}

/** Test evaluation of DW_CFA_restore */
- (void) testRestore {
    _stack.set_register(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, 0x20);
    uint8_t opcodes[] = { DW_CFA_val_offset, 0x4, 0x4, DW_CFA_restore|0x4};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, (int64_t)0x20);
}

/** Test evaluation of DW_CFA_restore_extended */
- (void) testRestoreExtended {
    _stack.set_register(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, 0x20);
    uint8_t opcodes[] = { DW_CFA_val_offset, 0x4, 0x4, DW_CFA_restore_extended, 0x4};
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, (int64_t)0x20);
}

/** Test evaluation of DW_CFA_remember_state */
- (void) testRememberState {
    /* Set up an initial state that the opcodes can push */
    _stack.set_register(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, 0x20);

    /* Push our current state, and then tweak register state (to verify that a new state is actually in place). */
    uint8_t opcodes[] = { DW_CFA_remember_state, DW_CFA_undefined, 0x4 };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);

    /* Restore our previous state and verify that it is unchanged */
    STAssertTrue(_stack.pop_state(), @"No new state was pushed");
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, (int64_t)0x20);
}

/** Test evaluation of DW_CFA_restore_state */
- (void) testRestoreState {
    /* Set up an initial state that the opcodes can pop */
    _stack.set_register(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, 0x20);
    STAssertTrue(_stack.push_state(), @"Insufficient allocation to push new state");

    /* Tweak register state (to verify that a new state is actually in place), and then restore previous state */
    uint8_t opcodes[] = { DW_CFA_undefined, 0x4, DW_CFA_restore_state };
    PERFORM_EVAL_TEST(opcodes, 0x0, PLCRASH_ESUCCESS);
    
    /* Our previous state should have been restored by our CFA program; verify that it is unchanged */
    TEST_REGISTER_RESULT(0x4, PLCRASH_DWARF_CFA_REG_RULE_EXPRESSION, (int64_t)0x20);
}

- (void) testBadOpcode {
    uint8_t opcodes[] = { DW_CFA_BAD_OPCODE };
    PERFORM_EVAL_TEST(opcodes, 0, PLCRASH_ENOTSUP);
}

/** Test basic evaluation of a NOP. */
- (void) testNop {
    uint8_t opcodes[] = { DW_CFA_nop, };
    
    PERFORM_EVAL_TEST(opcodes, 0, PLCRASH_ESUCCESS);
}

/**
 * Walk the given thread state, searching for a valid general purpose register (eg, neither
 * the FP, SP, or IP) that can be used for test purposes.
 *
 * The idea here is to keep this test code non-architecture specific, relying on the thread state
 * API for any architecture-specific handling.
 */
- (plcrash_gen_regnum_t) determineTestRegister: (plcrash_async_thread_state_t *) ts {
    size_t count = plcrash_async_thread_state_get_reg_count(ts);

    /* Find a valid general purpose register */
    plcrash_gen_regnum_t reg;
    for (reg = (plcrash_gen_regnum_t)0; reg < count; reg++) {
        if (reg != PLCRASH_REG_FP && reg != PLCRASH_REG_SP && reg != PLCRASH_REG_IP)
            return reg;
    }

    STFail(@"Could not find register");
    __builtin_trap();
}

/**
 * Test handling of an undefined CFA value.
 */
- (void) testApplyCFAUndefined {
    plcrash_async_thread_state_t prev_ts;
    plcrash_async_thread_state_t new_ts;
    dwarf_cfa_state cfa_state;
    plcrash_error_t err;
    
    plcrash_async_thread_state_mach_thread_init(&prev_ts, mach_thread_self());
    err = plcrash_async_dwarf_cfa_state_apply(mach_task_self(), &prev_ts, &cfa_state, &new_ts);
    STAssertEquals(err, PLCRASH_EINVAL, @"Attempt to apply an incomplete CFA state did not return EINVAL");
}

/**
 * Test derivation of the CFA value from the given register.
 */
- (void) testApplyCFARegister {
    plcrash_async_thread_state_t prev_ts;
    plcrash_async_thread_state_t new_ts;
    dwarf_cfa_state cfa_state;
    plcrash_error_t err;

    plcrash_async_thread_state_mach_thread_init(&prev_ts, mach_thread_self());
    err = plcrash_async_dwarf_cfa_state_apply(mach_task_self(), &prev_ts, &cfa_state, &new_ts);
    STAssertEquals(err, PLCRASH_ESUCCESS, @"Failed to apply CFA state");

}

@end