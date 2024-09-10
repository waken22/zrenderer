module uniqueid;

import std.bitmanip : nativeToLittleEndian;
import std.array : appender;
import std.string : format;
import config : Config, Gender, toInt;
import draw : Canvas;

string createUid(uint jobid, immutable(Config) config, immutable(Canvas) canvas) pure nothrow @safe
{
    const data = configToByteArray(jobid, config, canvas);

    import std.digest.crc : crc32Of, crcHexString;

    return crcHexString(data.crc32Of);
}

private ubyte[] configToByteArray(uint jobid, immutable(Config) config, immutable(Canvas) canvas) pure nothrow @safe
{
    immutable sz = int.sizeof;
    auto buffer = new ubyte[sz * 24];

    auto i = 0;

    if (jobid < uint.max)
    {
        buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(jobid);
    }
    else
    {
        import std.digest.crc : crc32Of;
        import std.string : representation;
        import std.array : join;

        buffer[(sz * i) .. (sz * (++i))] = config.job.join(",").representation.crc32Of;
    }
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.action);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.frame);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.gender.toInt());
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.head);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.outfit);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.garment);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.weapon);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.shield);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.bodyPalette);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.headPalette);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.headdir.toInt());
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.madogearType.toInt());
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.enableShadow ? 1 : 0);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.ignoreBaby ? 1 : 0);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.outputFormat.toInt());
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(canvas.width);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(canvas.height);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(canvas.originx);
    buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(canvas.originy);

    import std.algorithm : min;

    const numheadgear = min(4, config.headgear.length);

    foreach (h; 0 .. numheadgear)
    {
        buffer[(sz * i) .. (sz * (++i))] = nativeToLittleEndian(config.headgear[h]);
    }

    return buffer[0 .. (sz * i)];
}
