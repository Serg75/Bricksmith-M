//==============================================================================
//
//  File:       LDrawRebrickable.h
//  Package:    LDrawRebrickable
//
//  Purpose:    Umbrella header. Gets part data from Rebrickable: the CSV
//              downloads, the catalog and set list built from them, set
//              imports, the color table, and a small API client. The only
//              package that touches the network. Depends on LDrawInventory.
//
//              Data from Rebrickable.com. Its terms ask for that credit, and
//              for automated downloads at most once a day.
//
//  Created by Sergey Slobodenyuk on 2026-10-26.
//
//==============================================================================

#import <Foundation/Foundation.h>

#import <LDrawRebrickable/LDrawRebrickableCatalog.h>
#import <LDrawRebrickable/LDrawRebrickableClient.h>
#import <LDrawRebrickable/LDrawRebrickableColors.h>
#import <LDrawRebrickable/LDrawRebrickableCSVReader.h>
#import <LDrawRebrickable/LDrawRebrickableDownloads.h>
#import <LDrawRebrickable/LDrawRebrickableSetImporter.h>
#import <LDrawRebrickable/LDrawRebrickableSetList.h>
