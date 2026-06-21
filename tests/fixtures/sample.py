import logging

logger = logging.getLogger(__name__)


def compute(values):
    logger.debug(
        "computing over %d values: %s",
        len(values),
        values,
    )
    total = 0
    for v in values:
        total += v
    print("partial", total)
    logging.info("done computing")
    return total


def chatty():
    print("a")
    print("b")
    print("c")
    return 1
