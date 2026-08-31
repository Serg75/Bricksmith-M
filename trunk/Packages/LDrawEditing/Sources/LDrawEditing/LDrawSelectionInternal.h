//==============================================================================
//
//  File:       LDrawSelectionInternal.h
//  Package:    LDrawEditing
//
//  Purpose:    Private constants shared across LDrawSelection categories.
//
//  Info:       Not part of the public module API.
//
//  Created by Sergey Slobodenyuk on 2026-08-31.
//
//==============================================================================

#ifndef LDrawSelectionInternal_h
#define LDrawSelectionInternal_h

#import <Foundation/Foundation.h>

// Match NSEventModifierFlags so AppKit hosts pass event.modifierFlags through.
static const NSUInteger kLDrawModifierShift   = 1UL << 17;
static const NSUInteger kLDrawModifierOption  = 1UL << 19;
static const NSUInteger kLDrawModifierCommand = 1UL << 20;

#endif /* LDrawSelectionInternal_h */
