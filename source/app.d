module app;

import config : Config, Gender, HeadDirection, OutputFormat, MadogearType, NoJobId, ignoreBaby;
import draw : Canvas, canvasFromString;
import logging : LogLevel, LogDg;
import luad.state : LuaState;
import resolver;
import resource : ResourceManager, ResourceException, ImfResource;
import sprite;
import std.zip : ZipArchive;
import validation;

void createOutputDirectory(string outputDirectory) @safe
{
    import std.file : mkdirRecurse, exists;

    if (!outputDirectory.exists)
    {
        mkdirRecurse(outputDirectory);
    }
}

string[] run(immutable Config config, LogDg log, LuaState L = null,
        ResourceManager resManager = null, Resolver resolve = null)
{
    // Nothing to draw
    if (config.job.length == 0)
    {
        return [];
    }

    if (L is null)
    {
        import luad.error : LuaErrorException;

        try
        {
            L = new LuaState;
            L.openLibs();
        }
        catch (LuaErrorException err)
        {
            log(LogLevel.critical, err.msg);
            return [];
        }
    }

    if (resManager is null)
    {
        resManager = new ResourceManager(config.resourcepath);

        import luamanager : loadRequiredLuaFiles;
        import resource : ResourceException;

        try
        {
            loadRequiredLuaFiles(L, resManager, log);
        }
        catch (ResourceException err)
        {
            log(LogLevel.critical, err.msg);
            return [];
        }
    }

    if (resolve is null)
    {
        resolve = new Resolver(L);
    }

    return process(config, log, L, resManager, resolve);
}

string[] process(immutable Config config, LogDg log, LuaState L,
        ResourceManager resManager, Resolver resolve)
{
    string[] filenames;

    immutable(Canvas) canvas = canvasFromString(config.canvas);

    import std.zip : ZipArchive;

    ZipArchive archive;
    string zipFilename;

    if (config.outputFormat == OutputFormat.zip)
    {
        archive = new ZipArchive();

        if (config.enableUniqueFilenames)
        {
            import uniqueid : createUid;

            zipFilename = createUid(uint.max, config, canvas);
        }
        else
        {
            import std.datetime.systime : Clock, SysTime;
            import std.format : format;
            try
            {
                auto now = Clock.currTime();
                zipFilename = format("%04d-%02d-%02d-%02d-%02d", now.year, now.month, now.day, now.hour, now.minute);
            }
            catch (Exception err)
            {
                log(LogLevel.error, err.msg);
                zipFilename = "nodate-result";
            }
        }

        if (config.returnExistingFiles)
        {
            string[] existingFiles = existingFilenames(zipFilename, config.outdir, config.outputFormat);

            if (existingFiles.length > 0)
            {
                return existingFiles;
            }
        }
    }

    foreach (jobidstr; config.job)
    {
        uint startJob;
        uint endJob;
        float animationInterval = 12;
        int requestFrame = config.frame;

        import std.algorithm.searching : countUntil;
        import std.string : representation;

        auto rangeIndex = countUntil(jobidstr.representation, '-');

        import std.conv : to, ConvException;

        // We don't catch exceptions here because isJobArgValid should have taken care of errors
        if (rangeIndex < 0)
        {
            startJob = jobidstr == "none" ? NoJobId : jobidstr.to!uint;
            endJob = startJob;
        }
        else
        {
            startJob = jobidstr[0 .. rangeIndex].to!uint;
            endJob = jobidstr[rangeIndex + 1 .. $].to!uint;
        }

        for (auto jobid = startJob; jobid <= endJob; ++jobid)
        {
            string outputFilename;

            if (config.enableUniqueFilenames && config.outputFormat != OutputFormat.zip)
            {
                import uniqueid : createUid;

                outputFilename = createUid(jobid, config, canvas);
            }
            else
            {
                outputFilename = jobid == NoJobId ? "none" : jobid.to!string;
            }

            if (config.returnExistingFiles && config.outputFormat != OutputFormat.zip)
            {
                string[] existingFiles = existingFilenames(outputFilename, config.outdir, config.outputFormat);

                if (existingFiles.length > 0)
                {
                    filenames ~= existingFiles;
                    continue;
                }
            }


            Sprite[] sprites;

            ImfResource bodyImf = null;

            if (isPlayer(jobid))
            {
                sprites = processPlayer(jobid, log, config, resolve, resManager, L, animationInterval, requestFrame);

                bodyImf = imfForJob(jobid, config.gender, resolve, resManager);
            }
            else
            {
                sprites = processNonPlayer(jobid, log, config, resolve, resManager, L, animationInterval, requestFrame);
            }

            if (shouldDrawShadow(config.enableShadow, jobid, config.action))
            {
                log(LogLevel.trace, "Loading Shadow");
                auto shadowsprite = resManager.getSprite("shadow", SpriteType.shadow);
                shadowsprite.zIndex = -1;
                shadowsprite.loadImagesOfFrame(0, 0);

                import luamanager : shadowfactor;

                float scale = shadowfactor(jobid, L);
                if (scale >= -float.epsilon && scale <= float.epsilon)
                {
                    shadowsprite.modifyActSprite!"xScale"(0, 0, 0, 0);
                    shadowsprite.modifyActSprite!"yScale"(0, 0, 0, 0);
                }
                else if (scale > 0)
                {
                    shadowsprite.modifyActSprite!"xScale"(0, 0, 0, scale);
                    shadowsprite.modifyActSprite!"yScale"(0, 0, 0, scale);
                }

                sprites ~= shadowsprite;
            }

            import draw : RawImage;
            import renderer : drawPlayer;

            void sortIndexDelegate(ref int[] index, uint frame, ulong maxframes)
            {
                int direction = config.action % 8;
                const playerAction = intToPlayerAction(config.action);
                if (maxframes > 3 && (playerAction == PlayerAction.stand || playerAction == PlayerAction.sit))
                {
                    frame = frame / (maxframes - 1);
                }

                foreach (sprite; sprites)
                {
                    if (sprite.type == SpriteType.garment)
                    {
                        sprite.zIndex = zIndexForGarmentSprite(jobid, config.garment, config.action,
                                frame, config.gender, direction, L);
                    }
                    else if (sprite.type == SpriteType.playerhead && bodyImf !is null)
                    {
                        sprite.zIndex = zIndexForSprite(sprite, direction, config.action, frame, bodyImf);
                    }
                    else
                    {
                        sprite.zIndex = zIndexForSprite(sprite, direction);
                    }
                }

                import std.algorithm.sorting : makeIndex;

                makeIndex!"a.zIndex < b.zIndex"(sprites, index);
            }

            RawImage[] images = drawPlayer(sprites, config.action,
                    (requestFrame < 0) ? uint.max : requestFrame, &sortIndexDelegate, canvas);

            if (isBaby(jobid) && !config.ignoreBaby)
            {
                import renderer : applyBabyScaling;

                images.applyBabyScaling(0.75);
            }


            if (images.length > 0)
            {
                import filehelper : storeImages;

                auto fnames = storeImages(images, requestFrame, config, outputFilename, zipFilename, log,
                        animationInterval, archive);

                if (config.outputFormat != OutputFormat.zip)
                {
                    filenames ~= fnames;
                }
                else if (fnames.length > 0)
                {
                    // Delete the just created files because we only want the zip
                    import std.file : rmdirRecurse, FileException;
                    import std.path : dirName;

                    try
                    {
                        rmdirRecurse(dirName(fnames[0]));
                    }
                    catch (FileException err)
                    {
                        log(LogLevel.warning, "Couldn't delete directory: " ~ err.msg);
                    }
                }
            }
        }
    }

    if (config.outputFormat == OutputFormat.zip)
    {
        import std.path : buildPath;
        import std.file : write, rmdirRecurse, FileException;

        auto filename = buildPath(config.outdir, zipFilename ~ ".zip");

        write(filename, archive.build());

        filenames ~= filename;

        try
        {
            // Delete the just created directory because we only want the zip
            rmdirRecurse(buildPath(config.outdir, zipFilename));
        }
        catch (FileException err)
        {
            log(LogLevel.warning, "Couldn't delete directory: " ~ err.msg);
        }
    }

    return filenames;
}

Sprite[] processNonPlayer(uint jobid, LogDg log, immutable Config config, Resolver resolve,
        ResourceManager resManager, ref LuaState L, out float interval, ref int requestFrame)
{
    bool overwriteFrame = false;

    const jobspritepath = resolve.nonPlayerSprite(jobid);
    if (jobspritepath.length == 0)
    {
        return [];
    }

    Sprite jobsprite;

    try
    {
        log(LogLevel.trace, "Loading Body " ~ jobspritepath);
        jobsprite = resManager.getSprite(jobspritepath);
        jobsprite.zIndex = 0;
    }
    catch (ResourceException err)
    {
        log(LogLevel.error, err.msg);
        return [];
    }

    auto sprites = [jobsprite];

    interval = jobsprite.act.action(config.action).interval;

    if (isMercenary(jobid))
    {
        const playerAction = intToPlayerAction(config.action);
        overwriteFrame = config.headdir != HeadDirection.all && config.frame < 0 &&
            (playerAction == PlayerAction.stand || playerAction == PlayerAction.sit);

        const gender = (jobid - 6017) <= 9 ? Gender.female : Gender.male;

        const numBodyFrames = jobsprite.act.numberOfFrames(config.action);
        if (numBodyFrames <= 1)
        {
            // Force using the first frame for actions such as FREEZE, DEAD & FREEZE2
            requestFrame = 0;
        }

        // Attach head to mercenary. Gender is derived from the job id
        auto headspritepath = resolve.playerHeadSprite(jobid, config.head, gender);
        if (headspritepath.length > 0)
        {
            log(LogLevel.trace, "Loading Head " ~ headspritepath);
            auto headsprite = resManager.getSprite(headspritepath);
            headsprite.zIndex = 1;
            headsprite.parent(jobsprite);

            if (config.frame < 0)
            {
                headsprite.loadImagesOfAction(config.action);
            }
            else
            {
                headsprite.loadImagesOfFrame(config.action, config.frame);
            }
            sprites ~= headsprite;
        }

        // Attach weapon
        if (config.weapon > 0)
        {
            auto weaponspritepath = resolve.weaponSprite(jobid, 1, gender);
            if (weaponspritepath.length > 0)
            {
                try
                {
                    log(LogLevel.trace, "Loading Weapon " ~ weaponspritepath);
                    auto weaponsprite = resManager.getSprite(weaponspritepath, SpriteType.weapon);
                    weaponsprite.typeOrder = 0;
                    weaponsprite.zIndex = 2;
                    sprites ~= weaponsprite;

                    if (jobid < 6017 || jobid > 6026)
                    {
                        log(LogLevel.trace, "Loading Weapon Slash " ~ weaponspritepath ~ "_검광");
                        // Weapon Slash only for lancer & swordsman
                        auto weaponslashsprite = resManager.getSprite(weaponspritepath ~ "_검광", SpriteType.weapon);
                        weaponslashsprite.typeOrder = 1;
                        weaponslashsprite.zIndex = 3;
                        sprites ~= weaponslashsprite;
                    }
                }
                catch (ResourceException err)
                {
                    log(LogLevel.warning, err.msg);
                }
            }
        }

        if (config.headgear.length > 0)
        {
            import std.algorithm : min;

            // Mercenaries can have 4 headgears
            const numHeadgears = min(4, config.headgear.length);

            for (auto h = 0; h < numHeadgears; ++h)
            {
                if (config.headgear[h] > 0)
                {
                    const headgearspritepath = resolve.headgearSprite(config.headgear[h], gender);
                    try
                    {
                        log(LogLevel.trace, "Loading Headgear " ~ headgearspritepath);
                        auto headgearsprite = resManager.getSprite(headgearspritepath, SpriteType.accessory);
                        headgearsprite.typeOrder = h;
                        headgearsprite.zIndex = 4 + h;
                        headgearsprite.parent(jobsprite);
                        headgearsprite.headdir = config.headdir;
                        sprites ~= headgearsprite;

                        // Set to all frames if headgear has more frames
                        if (headgearsprite.act.frames(config.action).length > 3)
                        {
                            overwriteFrame = false;
                        }
                    }
                    catch (ResourceException err)
                    {
                        log(LogLevel.warning, err.msg);
                    }
                }
            }
        }
    }
    if (requestFrame < 0)
    {
        foreach (sprite; sprites)
        {
            sprite.loadImagesOfAction(config.action);
        }
    }
    else
    {
        foreach (sprite; sprites)
        {
            if (sprite.type == SpriteType.accessory && sprite.act.frames(config.action).length > 3)
            {
                sprite.loadImagesOfFrame(config.action,
                        cast(uint)((requestFrame % 3) * sprite.act.frames(config.action).length / 3));
            }
            else
            {
                sprite.loadImagesOfFrame(config.action, requestFrame);
            }
        }
    }

    return sprites;
}

Sprite[] processPlayer(uint jobid, LogDg log, immutable Config config, Resolver resolve,
        ResourceManager resManager, ref LuaState L, out float interval, ref int requestFrame)
{
    import std.exception : ErrnoException;

    import std.stdio : writeln;

    uint direction = config.action % 8;

    const playerAction = intToPlayerAction(config.action);
    bool overwriteFrame = config.headdir != HeadDirection.all && config.frame < 0 &&
        (playerAction == PlayerAction.stand || playerAction == PlayerAction.sit);

    Sprite bodysprite;
    bool useOutfit = false;

    try
    {
        bodysprite = loadBodySprite(jobid, config.outfit, config.gender, config.madogearType, resolve, resManager, log, useOutfit);
    }
    catch (ResourceException err)
    {
        log(LogLevel.error, err.msg);
        return [];
    }

    interval = bodysprite.act.action(config.action).interval;
    const numBodyFrames = bodysprite.act.numberOfFrames(config.action);
    if (numBodyFrames <= 1)
    {
        // Force using the first frame for actions such as FREEZE, DEAD & FREEZE2
        requestFrame = 0;
    }

    Sprite[] sprites;
    sprites.reserve(10);

    sprites ~= bodysprite;

    const headspritepath = resolve.playerHeadSprite(jobid, config.head, config.gender);
    Sprite headsprite;

    try
    {
        log(LogLevel.trace, "Loading Head " ~ headspritepath);
        headsprite = resManager.getSprite(headspritepath, SpriteType.playerhead);
        headsprite.parent(bodysprite);
        headsprite.headdir = config.headdir;
        sprites ~= headsprite;
    }
    catch (ResourceException err)
    {
        log(LogLevel.warning, err.msg);
    }

    if ((config.weapon > 0 || resolver.isMadogear(jobid)) && jobid != NoJobId)
    {
        const weaponspritepath = resolve.weaponSprite(jobid, config.weapon, config.gender, config.madogearType);
        if (weaponspritepath.length > 0)
        {
            if (!resolver.isMadogear(jobid)) // Madogear do not have a weapon, only weapon slash
            {
                try
                {
                    log(LogLevel.trace, "Loading Weapon " ~ weaponspritepath);
                    auto weaponsprite = resManager.getSprite(weaponspritepath, SpriteType.weapon);
                    weaponsprite.typeOrder = 0;
                    sprites ~= weaponsprite;
                }
                catch (ResourceException err)
                {
                    log(LogLevel.warning, err.msg);
                }
            }

            try
            {
                // Weapon Slash
                log(LogLevel.trace, "Loading Weapon Slash " ~ weaponspritepath ~ "_검광");
                auto weaponslashsprite = resManager.getSprite(weaponspritepath ~ "_검광", SpriteType.weapon);
                weaponslashsprite.typeOrder = 1;
                sprites ~= weaponslashsprite;
            }
            catch (ResourceException err)
            {
                log(LogLevel.warning, err.msg);
            }
        }
    }

    if (config.shield > 0 && jobid != NoJobId)
    {
        const shieldspritepath = resolve.shieldSprite(jobid, config.shield, config.gender);
        if (shieldspritepath.length > 0)
        {
            try
            {
                log(LogLevel.trace, "Loading Shield " ~ shieldspritepath);
                auto shieldsprite = resManager.getSprite(shieldspritepath, SpriteType.shield);
                sprites ~= shieldsprite;
            }
            catch (ResourceException err)
            {
                log(LogLevel.warning, err.msg);
            }
        }
    }

    if (config.headgear.length > 0)
    {
        import std.algorithm : min;

        const numHeadgears = min(3, config.headgear.length);

        for (auto h = 0; h < numHeadgears; ++h)
        {
            if (config.headgear[h] > 0)
            {
                const headgearspritepath = resolve.headgearSprite(config.headgear[h], config.gender);
                try
                {
                    log(LogLevel.trace, "Loading Headgear " ~ headgearspritepath);
                    auto headgearsprite = resManager.getSprite(headgearspritepath, SpriteType.accessory);
                    headgearsprite.typeOrder = h;
                    headgearsprite.parent(bodysprite);
                    headgearsprite.headdir = config.headdir;

                    if (isDoram(jobid))
                    {
                        import luamanager : headgearOffsetForDoram;

                        const additionaloffset = headgearOffsetForDoram(config.headgear[h], direction, config.gender, L);
                        if (additionaloffset != additionaloffset.init)
                        {
                            headgearsprite.addOffsetToAttachPoint(config.action, config.frame, 0, -additionaloffset.x, -additionaloffset.y);
                        }
                    }

                    sprites ~= headgearsprite;

                    // Set to all frames if headgear has more frames
                    if (headgearsprite.act.frames(config.action).length > 3)
                    {
                        overwriteFrame = false;
                    }
                }
                catch (ResourceException err)
                {
                    log(LogLevel.warning, err.msg);
                }
            }
        }
    }

    if (config.garment > 0 && jobid != NoJobId && !isMadogear(jobid))
    {
        auto garmentspritepath = resolve.garmentSprite(jobid, config.garment, config.gender);
        if (garmentspritepath.length > 0)
        {
            import resource : ActResource, SprResource;

            auto garmentactpath = garmentspritepath;
            auto garmentsprpath = garmentactpath;

            if (!resManager.exists!ActResource(garmentspritepath))
            {
                // The korean name doesn't seem to exist. Let's just try with the english name
                // If it also doesn't exist the following try block will catch the exception.
                garmentactpath = resolve.garmentSprite(jobid, config.garment, config.gender, true);
                garmentsprpath = garmentactpath;
            }
            if (!resManager.exists!SprResource(garmentsprpath))
            {
                // We are not trying the english fallback in hope that the newer garments will follow the
                // current implementations and use latin names for both. Only the newer garments seem
                // to omit the duplicate .spr files for each job.
                garmentsprpath = resolve.garmentSprite(jobid, config.garment, config.gender, false, true);
            }
            try
            {
                log(LogLevel.trace, "Loading Garment (act) " ~ garmentactpath);
                log(LogLevel.trace, "Loading Garment (spr) " ~ garmentsprpath);
                auto garmentsprite = resManager.getSprite(garmentactpath, garmentsprpath, SpriteType.garment);
                //garmentsprite.parent(bodysprite); // Apparently garments are not attached to the body?
                sprites ~= garmentsprite;

                // Set to all frames if garment has more frames
                if (garmentsprite.act.frames(config.action).length > 3)
                {
                    overwriteFrame = false;
                }
            }
            catch (ResourceException err)
            {
                log(LogLevel.warning, err.msg);
            }
        }
    }

    import resource : Palette, PaletteResource;

    PaletteResource bodypalette;
    PaletteResource headpalette;

    if (config.bodyPalette > -1 && jobid != NoJobId)
    {
        string bodypalettepath;
        if (config.outfit > 0 && useOutfit)
        {
            bodypalettepath = resolve.bodyAltPalette(jobid, config.bodyPalette, config.gender, config.outfit, config.madogearType);
        }
        else
        {
            bodypalettepath = resolve.bodyPalette(jobid, config.bodyPalette, config.gender, config.madogearType);
        }

        if (bodypalettepath.length > 0)
        {
            try
            {
                log(LogLevel.trace, "Loading Body Palette " ~ bodypalettepath);
                bodypalette = resManager.get!PaletteResource(bodypalettepath);
                bodypalette.load();
            }
            catch (ResourceException err)
            {
                log(LogLevel.warning, err.msg);
            }
        }
    }

    if (config.headPalette > -1)
    {
        auto headpalettepath = resolve.headPalette(jobid, config.head, config.headPalette, config.gender);
        if (headpalettepath.length > 0)
        {
            try
            {
                log(LogLevel.trace, "Loading Head Palette " ~ headpalettepath);
                headpalette = resManager.get!PaletteResource(headpalettepath);
                headpalette.load();
            }
            catch (ResourceException err)
            {
                log(LogLevel.warning, err.msg);
            }
        }
    }

    if (overwriteFrame)
    {
        import config : toInt;

        requestFrame = config.headdir.toInt();
    }

    if (requestFrame < 0)
    {
        foreach (sprite; sprites)
        {
            if (sprite.type == SpriteType.playerbody)
            {
                bodysprite.loadImagesOfAction(config.action,
                        bodypalette !is null && bodypalette.usable ? bodypalette.palette : Palette.init);
            }
            else if (sprite.type == SpriteType.playerhead)
            {
                headsprite.loadImagesOfAction(config.action,
                        headpalette !is null && headpalette.usable ? headpalette.palette : Palette.init);
            }
            else
            {
                sprite.loadImagesOfAction(config.action);
            }
        }
    }
    else
    {
        foreach (sprite; sprites)
        {
            if (sprite.type == SpriteType.playerbody)
            {
                bodysprite.loadImagesOfFrame(config.action, requestFrame,
                        bodypalette !is null && bodypalette.usable ? bodypalette.palette : Palette.init);
            }
            else if (sprite.type == SpriteType.playerhead)
            {
                headsprite.loadImagesOfFrame(config.action, requestFrame,
                        headpalette !is null && headpalette.usable ? headpalette.palette : Palette.init);
            }
            else if (sprite.type == SpriteType.accessory && sprite.act.frames(config.action).length > 3)
            {
                sprite.loadImagesOfFrame(config.action,
                        cast(uint)((requestFrame % 3) * sprite.act.frames(config.action).length / 3));
            }
            else
            {
                sprite.loadImagesOfFrame(config.action, requestFrame);
            }
        }
    }

    return sprites;
}

bool shouldDrawShadow(bool enableShadow, uint jobid, uint action) pure nothrow @safe @nogc
{
    if (!enableShadow || jobid == NoJobId)
    {
        return false;
    }

    if (isPlayer(jobid) || isMercenary(jobid))
    {
        const playerAction = intToPlayerAction(action);

        if (playerAction == PlayerAction.sit || playerAction == PlayerAction.dead)
        {
            return false;
        }
    }
    else if (!isNPC(jobid))
    {
        const monsterAction = intToMonsterAction(action);

        if (monsterAction == MonsterAction.dead)
        {
            return false;
        }
    }

    return true;
}

/// Throws ResourceException
private Sprite loadBodySprite(uint jobid, uint outfitid, const scope Gender gender,
        const scope MadogearType madogearType, Resolver resolve, ResourceManager resManager,
        LogDg log, out bool useOutfit)
{
    useOutfit = false;

    if (jobid == NoJobId)
    {
        import resource.act : ActResource;
        import resource.spr : SprResource;
        import resource.empty_body_sprite : emptyBodyAct, emptyBodySpr;
        auto emptyAct = resManager.get!ActResource("emptyBody");
        auto emptySpr = resManager.get!SprResource("emptyBody");
        emptyAct.load(emptyBodyAct);
        emptySpr.load(emptyBodySpr);
        return resManager.getSprite(emptyAct, emptySpr, SpriteType.playerbody);
    }

    string bodyspritepath;
    Sprite bodysprite;

    if (outfitid > 0)
    {
        bodyspritepath = resolve.playerBodyAltSprite(jobid, gender, outfitid, madogearType);
        if (bodyspritepath.length > 0)
        {
            try
            {
                log(LogLevel.trace, "Loading Body " ~ bodyspritepath);
                bodysprite = resManager.getSprite(bodyspritepath, SpriteType.playerbody);
                useOutfit = true;
            }
            catch (ResourceException err)
            {
                // TODO show message to user?
            }
        }
    }

    if (!useOutfit)
    {
        bodyspritepath = resolve.playerBodySprite(jobid, gender, madogearType);

        import std.exception : enforce;
        import std.format : format;

        enforce!ResourceException(bodyspritepath.length > 0,
                format("Couldn't resolve player body sprite for job %d and gender %s", jobid, gender));

        log(LogLevel.trace, "Loading Body " ~ bodyspritepath);
        bodysprite = resManager.getSprite(bodyspritepath, SpriteType.playerbody);
    }

    return bodysprite;
}

private string[] existingFilenames(const scope string filename, const scope string outdir, OutputFormat outputFormat)
{
    import std.path : buildPath;
    import std.file : exists;

    if (outputFormat == OutputFormat.zip)
    {
        const file = buildPath(outdir, filename ~ ".zip");
        if (exists(file))
        {
            return [file];
        }

        return [];
    }

    const path = buildPath(outdir, filename);

    if (exists(path))
    {
        import std.array : array;
        import std.algorithm : each, filter, map;
        import std.file : dirEntries, SpanMode, FileException;
        import std.path : baseName;

        try
        {
            return dirEntries(path, "*.png", SpanMode.shallow, false)
                .filter!(entry => entry.isFile)
                .map!(entry => buildPath(path, baseName(entry.name)))
                .array;
        }
        catch (FileException err)
        {
            // Fall through
        }
    }

    return [];
}

private ImfResource imfForJob(uint jobid, const scope Gender gender,
        Resolver resolve, ResourceManager resManager)
{
    if (jobid == NoJobId)
    {
        return null;
    }

    const imfName = resolve.imfName(jobid, gender);

    if (imfName.length > 0)
    {
        try
        {
            ImfResource imf = resManager.get!ImfResource(imfName);
            imf.load();

            return imf;
        }
        catch (ResourceException err)
        {
            // Fall through
        }
    }

    return null;
}

