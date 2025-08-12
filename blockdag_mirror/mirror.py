import os
import logging
from github import Github
from .utils import run_cmd

# Configure a module-level logger
logger = logging.getLogger(__name__)



def list_repos(src_org: str):
    """Return an iterable of repositories for the given source organisation.

    Uses the SRC_GH_TOKEN environment variable for authentication.

    Args:
        src_org: Organisation slug to mirror from.

    Returns:
        Iterable of PyGithub Repository objects.

    Raises:
        EnvironmentError: if the SRC_GH_TOKEN is not set.
    """
    token = os.getenv("SRC_GH_TOKEN")
    if not token:
        raise EnvironmentError("SRC_GH_TOKEN environment variable not set.")
    gh = Github(token)
    org = gh.get_organization(src_org)
    return org.get_repos()



def mirror_repo(repo, dest_org: str, dest_token: str):
    """Mirror a single repository from the source to a destination organisation.

    Clones a bare mirror of the repo, then force pushes all refs to the destination.

    Args:
        repo: PyGithub Repository object from the source organisation.
        dest_org: Destination organisation slug.
        dest_token: Personal access token for the destination account.
    """
    name = repo.name
    # Build authenticated clone URLs for source and destination
    src_token = os.getenv("SRC_GH_TOKEN")
    src_url = repo.clone_url.replace("https://", f"https://{src_token}@")
    dest_url = f"https://{dest_token}@github.com/{dest_org}/{name}.git"
    tmp_dir = f"/tmp/{name}.git"
    # Clean up any existing clone
    if os.path.exists(tmp_dir):
        run_cmd(["rm", "-rf", tmp_dir])
    logger.info("Cloning %s", name)
    run_cmd(["git", "clone", "--mirror", src_url, tmp_dir])
    logger.info("Pushing %s to %s", name, dest_org)
    run_cmd(["git", "--git-dir", tmp_dir, "push", "--mirror", "--prune", dest_url])
    run_cmd(["rm", "-rf", tmp_dir])



def run_mirror():
    """Mirror all repositories from SRC_ORG to all configured destinations.

    Destination organisations and their tokens are read from environment
    variables. Requires that SRC_ORG, SRC_GH_TOKEN and all DST_*_TOKEN
    variables are set.
    """
    src_org = os.getenv("SRC_ORG")
    if not src_org:
        raise EnvironmentError("SRC_ORG environment variable not set.")
    dests = [
        (os.getenv("DST_STRAT_ORG", "Strattice"), os.getenv("DST_STRAT_TOKEN")),
        (os.getenv("DST_BRAIN_ORG", "BrainstormOnline"), os.getenv("DST_BRAIN_TOKEN")),
        (os.getenv("DST_ENG_ORG", "BlockDAG-Engineering"), os.getenv("DST_ENG_TOKEN")),
    ]
    repos = list_repos(src_org)
    for repo in repos:
        for dest_org, token in dests:
            if not token:
                logger.warning("No token provided for destination %s; skipping", dest_org)
                continue
            try:
                mirror_repo(repo, dest_org, token)
            except Exception as exc:
                logger.exception("Failed to mirror %s to %s: %s", repo.name, dest_org, exc)
